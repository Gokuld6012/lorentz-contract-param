{-# LANGUAGE DeriveAnyClass, DerivingStrategies #-}
{-# OPTIONS_GHC -Wno-redundant-constraints #-}

-- | Instructions working on product types derived from Haskell ones.
module Michelson.Typed.Haskell.Instr.Product
  ( InstrGetC
  , InstrSetC
  , InstrConstructC
  , instrGet
  , instrSet
  , instrConstruct

  , ConstructorFieldTypes
  , FieldConstructor (..)
  ) where

import qualified Data.Kind as Kind
import Data.Type.Bool (If)
import Data.Type.Equality (type (==))
import Data.Vinyl.Core (Rec(..))
import Data.Vinyl.Derived (Label)
import Data.Vinyl.TypeLevel (type (++))
import GHC.Generics ((:*:)(..), (:+:)(..))
import qualified GHC.Generics as G
import GHC.TypeLits (ErrorMessage(..), Symbol, TypeError)
import Named ((:!), (:?), NamedF(..))

import Michelson.Typed.Haskell.Instr.Helpers
import Michelson.Typed.Haskell.Value
import Michelson.Typed.Instr
import Util.Named (NamedInner)

-- Fields lookup (helper)
----------------------------------------------------------------------------

-- | Result of field lookup - its type and path to it in
-- the tree.
data LookupNamedResult = LNR Kind.Type Path

type family LnrFieldType (lnr :: LookupNamedResult) where
  LnrFieldType ('LNR f _) = f
type family LnrBranch (lnr :: LookupNamedResult) :: Path where
  LnrBranch ('LNR _ p) = p

-- | Find field of some product type by its name.
--
-- Name might be either field record name, or one in 'NamedF' if
-- field is wrapped using '(:!)' or '(:?)'.
type GetNamed name a = LNRequireFound name a (GLookupNamed name (G.Rep a))

-- | Force result of 'GLookupNamed' to be 'Just'
type family LNRequireFound
  (name :: Symbol)
  (a :: Kind.Type)
  (mf :: Maybe LookupNamedResult)
    :: LookupNamedResult where
  LNRequireFound _ _ ('Just lnr) = lnr
  LNRequireFound name a 'Nothing = TypeError
    ('Text "Datatype " ':<>: 'ShowType a ':<>:
     'Text " has no field " ':<>: 'ShowType name)

type family GLookupNamed (name :: Symbol) (x :: Kind.Type -> Kind.Type)
          :: Maybe LookupNamedResult where
  GLookupNamed name (G.D1 _ x) = GLookupNamed name x
  GLookupNamed name (G.C1 _ x) = GLookupNamed name x

  GLookupNamed name (G.S1 ('G.MetaSel ('Just recName) _ _ _) (G.Rec0 a)) =
    If (name == recName)
      ('Just $ 'LNR a '[])
      'Nothing
  GLookupNamed name (G.S1 _ (G.Rec0 (NamedF f a fieldName))) =
    If (name == fieldName)
      ('Just $ 'LNR (NamedInner (NamedF f a fieldName)) '[])
      'Nothing
  GLookupNamed _ (G.S1 _ _) = 'Nothing

  GLookupNamed name (x :*: y) =
    LNMergeFound name (GLookupNamed name x) (GLookupNamed name y)
  GLookupNamed name (_ :+: _) = TypeError
    ('Text "Cannot seek for a field " ':<>: 'ShowType name ':<>:
     'Text " in sum type")
  GLookupNamed _ G.U1 = 'Nothing
  GLookupNamed _ G.V1 = TypeError
    ('Text "Cannot access fields of void-like type")

type family LNMergeFound
  (name :: Symbol)
  (f1 :: Maybe LookupNamedResult)
  (f2 :: Maybe LookupNamedResult)
    :: Maybe LookupNamedResult where
  LNMergeFound _ 'Nothing 'Nothing = 'Nothing
  LNMergeFound _ ('Just ('LNR a p)) 'Nothing = 'Just $ 'LNR a ('L ': p)
  LNMergeFound _ 'Nothing ('Just ('LNR a p)) = 'Just $ 'LNR a ('R ': p)
  LNMergeFound name ('Just _) ('Just _) = TypeError
    ('Text "Ambigous reference to datatype field: " ':<>: 'ShowType name)

----------------------------------------------------------------------------
-- Value accessing instruction
----------------------------------------------------------------------------

-- | Make an instruction which accesses given field of the given datatype.
instrGet
  :: forall dt name fieldTy st path.
     InstrGetC dt name fieldTy path
  => Label name -> Instr (ToT dt ': st) (ToT fieldTy ': st)
instrGet _ = gInstrGet @name @(G.Rep dt) @path @fieldTy

-- | Constraint for 'instrGet'.
type InstrGetC dt name fieldTy path =
  ( IsoValue dt, Generic dt
  , GInstrGet name (G.Rep dt)
      (LnrBranch (GetNamed name dt))
      (LnrFieldType (GetNamed name dt))
  , 'LNR fieldTy path ~ GetNamed name dt, GValueType (G.Rep dt) ~ ToT dt
  )

{- Note about bulkiness of `instrGet` type signature:

Read this only if you are going to modify the signature qualitatively.

It may seem that you can replace 'LnrBranch' and 'LnrFieldType' getters since
their result is already assigned to a type variable, but if you do so,
on attempt to access non-existing field GHC will prompt you a couple of huge
"cannot deduce type" errors along with desired "field is not present".
To make error messages clearer we prevent GHC from deducing 'GInstrAccess' when
no field is found via using those getters.
-}

-- | Generic traversal for 'instrAccess'.
class GIsoValue x =>
  GInstrGet
    (name :: Symbol)
    (x :: Kind.Type -> Kind.Type)
    (path :: Path)
    (fieldTy :: Kind.Type) where
  gInstrGet
    :: GIsoValue x
    => Instr (GValueType x ': s) (ToT fieldTy ': s)

instance GInstrGet name x path f => GInstrGet name (G.M1 t i x) path f where
  gInstrGet = gInstrGet @name @x @path @f

instance (IsoValue f, ToT f ~ ToT f') =>
         GInstrGet name (G.Rec0 f) '[] f' where
  gInstrGet = Nop

instance (GInstrGet name x path f, GIsoValue y) => GInstrGet name (x :*: y) ('L ': path) f where
  gInstrGet = CAR `Seq` gInstrGet @name @x @path @f

instance (GInstrGet name y path f, GIsoValue x) => GInstrGet name (x :*: y) ('R ': path) f where
  gInstrGet = CDR `Seq` gInstrGet @name @y @path @f

-- Examples
----------------------------------------------------------------------------

type MyType1 = ("int" :! Integer, "text" :! Text, "text2" :? Text)

_getIntInstr1 :: Instr (ToT MyType1 ': s) (ToT Integer ': s)
_getIntInstr1 = instrGet @MyType1 #int

_getTextInstr1 :: Instr (ToT MyType1 ': s) (ToT (Maybe Text) ': s)
_getTextInstr1 = instrGet @MyType1 #text2

data MyType2 = MyType2
  { getInt :: Integer
  , getText :: Text
  , getUnit :: ()
  , getMyType1 :: MyType1
  } deriving stock (Generic)
    deriving anyclass (IsoValue)

_getIntInstr2 :: Instr (ToT MyType2 ': s) (ToT () ': s)
_getIntInstr2 = instrGet @MyType2 #getUnit

_getIntInstr2' :: Instr (ToT MyType2 ': s) (ToT Integer ': s)
_getIntInstr2' = instrGet @MyType2 #getMyType1 `Seq` instrGet @MyType1 #int

----------------------------------------------------------------------------
-- Value modification instruction
----------------------------------------------------------------------------

-- | For given complex type @dt@ and its field @fieldTy@ update the field value.
instrSet
  :: forall dt name fieldTy st path.
     InstrSetC dt name fieldTy path
  => Label name -> Instr (ToT fieldTy ': ToT dt ': st) (ToT dt ': st)
instrSet _ = gInstrSet @name @(G.Rep dt) @path @fieldTy

-- | Constraint for 'instrSet'.
type InstrSetC dt name fieldTy path =
  ( IsoValue dt, Generic dt
  , GInstrSet name (G.Rep dt)
      (LnrBranch (GetNamed name dt))
      (LnrFieldType (GetNamed name dt))
  , 'LNR fieldTy path ~ GetNamed name dt, GValueType (G.Rep dt) ~ ToT dt
  )

-- | Generic traversal for 'instrSet'.
class GIsoValue x =>
  GInstrSet
    (name :: Symbol)
    (x :: Kind.Type -> Kind.Type)
    (path :: Path)
    (fieldTy :: Kind.Type) where
  gInstrSet
    :: Instr (ToT fieldTy ': GValueType x ': s) (GValueType x ': s)

instance GInstrSet name x path f => GInstrSet name (G.M1 t i x) path f where
  gInstrSet = gInstrSet @name @x @path @f

instance (IsoValue f, ToT f ~ ToT f') =>
         GInstrSet name (G.Rec0 f) '[] f' where
  gInstrSet = DIP DROP

instance (GInstrSet name x path f, GIsoValue y) => GInstrSet name (x :*: y) ('L ': path) f where
  gInstrSet =
    DIP (DUP `Seq` DIP CDR `Seq` CAR) `Seq`
    gInstrSet @name @x @path @f `Seq`
    PAIR

instance (GInstrSet name y path f, GIsoValue x) => GInstrSet name (x :*: y) ('R ': path) f where
  gInstrSet =
    DIP (DUP `Seq` DIP CAR `Seq` CDR) `Seq`
    gInstrSet @name @y @path @f `Seq`
    SWAP `Seq` PAIR

-- Examples
----------------------------------------------------------------------------

_setIntInstr1 :: Instr (ToT Integer ': ToT MyType2 ': s) (ToT MyType2 ': s)
_setIntInstr1 = instrSet @MyType2 #getInt

----------------------------------------------------------------------------
-- Value construction instruction
----------------------------------------------------------------------------

-- | Way to construct one of the fields in a complex datatype.
newtype FieldConstructor (st :: [k]) (field :: Kind.Type) =
  FieldConstructor (Instr (ToTs' st) (ToT field ': ToTs' st))

-- | For given complex type @dt@ and its field @fieldTy@ update the field value.
instrConstruct
  :: forall dt st. InstrConstructC dt
  => Rec (FieldConstructor st) (ConstructorFieldTypes dt)
  -> Instr st (ToT dt ': st)
instrConstruct = gInstrConstruct @(G.Rep dt)

-- | Types of all fields in a datatype.
type ConstructorFieldTypes dt = GFieldTypes (G.Rep dt)

-- | Constraint for 'instrConstruct'.
type InstrConstructC dt =
  ( IsoValue dt, Generic dt, GInstrConstruct (G.Rep dt)
  , GValueType (G.Rep dt) ~ ToT dt
  )

-- | Generic traversal for 'instrConstruct'.
class GIsoValue x => GInstrConstruct (x :: Kind.Type -> Kind.Type) where
  type GFieldTypes x :: [Kind.Type]
  gInstrConstruct :: Rec (FieldConstructor st) (GFieldTypes x) -> Instr st (GValueType x ': st)

instance GInstrConstruct x => GInstrConstruct (G.M1 t i x) where
  type GFieldTypes (G.M1 t i x) = GFieldTypes x
  gInstrConstruct = gInstrConstruct @x

instance ( GInstrConstruct x, GInstrConstruct y
         , RSplit (GFieldTypes x) (GFieldTypes y)
         ) => GInstrConstruct (x :*: y) where
  type GFieldTypes (x :*: y) = GFieldTypes x ++ GFieldTypes y
  gInstrConstruct fs =
    let (lfs, rfs) = rsplit fs
        linstr = gInstrConstruct @x lfs
        rinstr = gInstrConstruct @y rfs
    in linstr `Seq` DIP rinstr `Seq` PAIR

instance GInstrConstruct G.U1 where
  type GFieldTypes G.U1 = '[]
  gInstrConstruct RNil = UNIT

instance ( TypeError ('Text "Cannot construct sum type")
         , GIsoValue x, GIsoValue y
         ) => GInstrConstruct (x :+: y) where
  type GFieldTypes (x :+: y) = '[]
  gInstrConstruct = error "impossible"

instance IsoValue a => GInstrConstruct (G.Rec0 a) where
  type GFieldTypes (G.Rec0 a) = '[a]
  gInstrConstruct (FieldConstructor i :& RNil) = i

-- Examples
----------------------------------------------------------------------------

_constructInstr1 :: Instr (ToT MyType1 ': s) (ToT MyType2 ': ToT MyType1 ': s)
_constructInstr1 =
  instrConstruct @MyType2 $
    FieldConstructor (PUSH (toVal @Integer 5)) :&
    FieldConstructor (PUSH (toVal @Text "")) :&
    FieldConstructor UNIT :&
    FieldConstructor DUP :&
    RNil