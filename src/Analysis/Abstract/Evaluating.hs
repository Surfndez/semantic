{-# LANGUAGE GeneralizedNewtypeDeriving, TypeFamilies #-}
module Analysis.Abstract.Evaluating
( Evaluating
) where

import Control.Abstract.Analysis hiding (lower)
import qualified Control.Monad.Effect as Eff
import Control.Monad.Effect.Exception as Exc
import Data.Abstract.Environment
import Data.Abstract.Module
import Data.Abstract.ModuleTable
import Data.Abstract.Origin
import Data.Semilattice.Lower
import Prologue

-- | An analysis evaluating @term@s to @value@s with a list of @effects@ using 'Evaluatable', and producing incremental results of type @a@.
newtype Evaluating location term value effects a = Evaluating { runEvaluating :: Eff effects a }
  deriving (Applicative, Functor, Effectful, Monad)

deriving instance Member NonDet effects => Alternative (Evaluating location term value effects)

-- | Effects necessary for evaluating (whether concrete or abstract).
type EvaluatingEffects location term value
  = '[ Return value
     , Exc (LoopThrow value)
     , Fail                                        -- Failure with an error message
     , Fresh                                       -- For allocating new addresses and/or type variables.
     , Reader (SomeOrigin term)                    -- The current term’s origin.
     , Reader (ModuleTable [Module term])          -- Cache of unevaluated modules
     , Reader (Environment location value)         -- Default environment used as a fallback in lookupEnv
     , State  (EvaluatorState location term value) -- Environment, heap, modules, exports, and jumps.
     ]

instance ( Member (Reader (Environment location value)) effects
         , Member (Reader (ModuleTable [Module term])) effects
         , Member (Reader (SomeOrigin term)) effects
         , Member (State (EvaluatorState location term value)) effects
         )
      => MonadEvaluator location term value effects (Evaluating location term value)

instance ( Corecursive term
         , Member (Reader (Environment location value)) effects
         , Member (Reader (ModuleTable [Module term])) effects
         , Member (Reader (SomeOrigin term)) effects
         , Member (State (EvaluatorState location term value)) effects
         , Recursive term
         )
      => MonadAnalysis location term value effects (Evaluating location term value) where
  analyzeTerm eval term = pushOrigin (termOrigin (embedSubterm term)) (eval term)

  analyzeModule eval m = pushOrigin (moduleOrigin (subterm <$> m)) (eval m)


instance Interpreter (Evaluating location term value) (EvaluatingEffects location term value) where
  type Result (Evaluating location term value) (EvaluatingEffects location term value) result
    = ( Either String
      ( Either (LoopThrow value)
        result)
      , EvaluatorState location term value)
  interpret
    = interpret
    . runEvaluating
    . raiseHandler
      ( flip runState  lower -- State (EvaluatorState location term value)
      . flip runReader lower -- Reader (Environment location value)
      . flip runReader lower -- Reader (ModuleTable [Module term])
      . flip runReader lower -- Reader (SomeOrigin term)
      . flip runFresh' 0
      . runFail
      . Exc.runError
      . Eff.interpret (\ (Return value) -> pure value))
