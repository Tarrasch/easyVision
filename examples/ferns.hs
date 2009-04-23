-- Naive Bayes and "ferns"

import Numeric.LinearAlgebra
import Classifier as C
import System.Random
import Debug.Trace
import Data.List as L
import qualified Data.Map as M
import Data.Maybe(fromMaybe)
import Control.Arrow((&&&))
import System (getArgs)

--matrix m = fromLists m :: Matrix Double
--vector v = fromList v :: Vector Double

shErr d c = putStrLn $ (show $ 100 * errorRate d c) ++ " %"
shConf d c = putStrLn $ format " " (show.round) (confusion d c)

genRandFeats ran = do
    seed <- randomIO
    return $ partit $ randomRs ran (mkStdGen seed)
 where partit (a:b:rest) = (a,b):partit rest


study' prob meth = do
    let (train,test) = prob
    let (c,f) = meth train
    putStr "Training error: "
    shErr train c
    --shConf train c
    putStr "Test error: "
    shErr test c
    shConf test c

main = do
    m <- fromFile "../data/mnist.txt" (5000,785)
    args <- map read `fmap` getArgs
    let [n,s] = case args of
            [] -> error "usage: ./ferns <ferns number (e.g. 100)> <ferns size (e.g. 10) >"
            [n,s]->[n,s]
    let vs = toRows (takeColumns 784 m)
    let ls = map (show.round) $ toList $ flatten $ dropColumns 784 m
    seed <- randomIO
    let mnist = scramble seed $ zip vs ls
    let (train,test) = splitAt 4000 mnist

    randfeats <- take (n*s) `fmap` genRandFeats (0,783::Int)
    let train' = preprocess (randBinFeat randfeats) train
        test'  = preprocess (randBinFeat randfeats) test

    let rawproblem = (train,test)
    putStr "distmed "
    study' rawproblem (distance ordinary)
--    putStr "mselin "
--    study' rawproblem (multiclass mse)
    putStr "fastferns-1 "
    study' (train',test') (distance naiveBayes)

    let train'' = preprocess (binbool s randfeats) train
        test''  = preprocess (binbool s randfeats) test

    putStr "ferns-3 "
    study' (train'',test'') (distance ferns)

---------------------------------------------------------

randBinFeat coordPairs v = fromList $ map g coordPairs
    where g (a,b) = if v@>a > v@>b then 1.0 else 0.0 :: Double

vsum v = v <.> constant 1 (dim v)

naiveBayes :: Distance (Vector Double)
naiveBayes vs = f where
    Stat {meanVector = p} = stat (fromRows vs)
    f x = - (vsum $ log $ x*p + (1-x)*(1-p))

binbool k coordPairs v = partit k $ map g coordPairs
    where g (a,b) = v@>a > v@>b

ferns :: Distance [[Bool]]
ferns vs = f where
    hs = map histog (transpose vs)
    histog = M.fromList .map (head &&& lr) . L.group . sort
        where lr l = fromIntegral (length l) / t :: Double
    t = fromIntegral (length vs)
    f x = negate $ sum $ map log $ zipWith get hs x
        where get m v = fromMaybe (0.1/t) (M.lookup v m)
