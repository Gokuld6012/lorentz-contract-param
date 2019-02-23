-- | Tests for Morley.Runtime.

module Test.Morley.Runtime
  ( spec
  ) where

import Control.Lens (at)
import Test.Hspec
  (Expectation, Spec, context, describe, it, parallel, shouldBe, shouldSatisfy, specify)

import Michelson.Interpret
import Michelson.Types
import Morley.Runtime
import Morley.Runtime.GState (GState(..), initGState)

spec :: Spec
spec = describe "Morley.Runtime" $ do
  -- Safe to run in parallel, because 'interpreterPure' is pure.
  describe "interpreterPure" $ parallel $ do
    context "Updates storage value of executed contract" $ do
      specify "contract1" $ updatesStorageValue contractAux1
      specify "contract2" $ updatesStorageValue contractAux2
    it "Fails to originate an already originated contract" failsToOriginateTwice

----------------------------------------------------------------------------
-- Test code
----------------------------------------------------------------------------

data UnexpectedFailed =
  UnexpectedFailed MichelsonFailed
  deriving (Show)

instance Exception UnexpectedFailed

updatesStorageValue :: ContractAux -> Expectation
updatesStorageValue ca = either throwM handleResult $ do
  let
    contract = caContract ca
    ce = caEnv ca
    account = Account
      { accBalance = ceBalance ce
      , accStorage = ceStorage ce
      , accContract = contract
      }
  gState' <- _irGState <$>
    interpreterPure dummyNow initGState [OriginateOp account]
  -- Note: `contractAddress` most likely should require the
  -- contract to be originated, even though now it doesn't.
  let
    addr = contractAddress contract
    txData = TxData
      { tdSenderAddress = ceSender ce
      , tdParameter = ceParameter ce
      , tdAmount = Mutez 100
      }
  (addr,) <$> interpreterPure dummyNow gState' [TransferOp addr txData]
  where
    handleResult :: (Address, InterpreterRes) -> Expectation
    handleResult (addr, ir) = do
      expectedValue <-
        either (throwM . UnexpectedFailed) (pure . snd) $
        michelsonInterpreter (caEnv ca) (caContract ca)
      accStorage <$> (gsAccounts (_irGState ir) ^. at addr) `shouldBe`
        Just expectedValue

failsToOriginateTwice :: Expectation
failsToOriginateTwice =
  interpreterPure dummyNow initGState ops `shouldSatisfy`
  isAlreadyOriginated
  where
    contract = caContract contractAux1
    ce = caEnv contractAux1
    account = Account
      { accBalance = ceBalance ce
      , accStorage = ceStorage ce
      , accContract = contract
      }
    ops = [OriginateOp account, OriginateOp account]
    isAlreadyOriginated (Left (IEAlreadyOriginated {})) = True
    isAlreadyOriginated _ = False

----------------------------------------------------------------------------
-- Data
----------------------------------------------------------------------------

dummyNow :: Timestamp
dummyNow = Timestamp 100

dummyContractEnv :: ContractEnv
dummyContractEnv = ContractEnv
  { ceNow = dummyNow
  , ceMaxSteps = 100500
  , ceBalance = Mutez 100
  , ceStorage = ValueUnit
  , ceContracts = mempty
  , ceParameter = ValueUnit
  , ceSource = Address "x"
  , ceSender = Address "x"
  , ceAmount = Mutez 100
  }

-- Contract and auxiliary data
data ContractAux = ContractAux
  { caContract :: !(Contract Op)
  , caEnv :: !ContractEnv
  }

contractAux1 :: ContractAux
contractAux1 = ContractAux
  { caContract = contract
  , caEnv = env
  }
  where
    contract :: Contract Op
    contract = Contract
      { para = Type tstring noAnn
      , stor = Type tbool noAnn
      , code =
        [ Op $ CDR noAnn noAnn
        , Op $ NIL noAnn noAnn $ Type T_operation noAnn
        , Op $ PAIR noAnn noAnn noAnn noAnn
        ]
      }
    env :: ContractEnv
    env = dummyContractEnv
      { ceStorage = ValueTrue
      , ceParameter = ValueString "aaa"
      }

contractAux2 :: ContractAux
contractAux2 = contractAux1
  { caContract = (caContract contractAux1)
    { code =
      [ Op $ CDR noAnn noAnn
      , Op $ NOT noAnn
      , Op $ NIL noAnn noAnn $ Type T_operation noAnn
      , Op $ PAIR noAnn noAnn noAnn noAnn
      ]
    }
  }