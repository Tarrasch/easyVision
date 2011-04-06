-- ellipse detection and similar rectification from the images of circles

import EasyVision hiding ((.*))
import Graphics.UI.GLUT hiding (RGB,Size,minmax,histogram,Point,set,Matrix)
import qualified Data.Colour.Names as Col
import Numeric.GSL.Fourier
import Numeric.LinearAlgebra
--import Complex
import Control.Monad(when)
import Data.List(sortBy)
import Util.Misc(degree,unitary)
import Vision.Camera
import Util.Ellipses
import Numeric.GSL.Minimization
import Text.Printf
import Data.Maybe(isJust)
import Util.Homogeneous

import Util.Misc(Mat,pairsWith,debug,mean,diagl)
import Util.Covariance(covStr,meanV)
import Data.Maybe(catMaybes)
import Data.Colour.Names as Col hiding (gray)

sz' = Size 600 600

main = do

    sz <- findSize

    (cam, ctrl)  <- getCam 0 sz  ~> channels >>= withPause

    prepare

    o <- createParameters [("threshold",intParam 128 1 255),
                           ("area",percent 5),
                           ("tolerance",percent 10),
                           ("fracpix",realParam 0.8 0 10),
                           ("scale", realParam 1 0 5),
                           ("method", intParam 1 1 2)]

    w  <- evWindow () "Ellipses" sz  Nothing (const (kbdcam ctrl))
    depthFunc $= Just Less
    wr <- evWindow () "Rectif"   sz' Nothing (const (kbdcam ctrl))

    launch (worker w wr cam o)

-----------------------------------------------------------------

worker w wr cam param = do

    th2 <- fromIntegral `fmap` (getParam param "threshold" ::IO Int)
    area <- getParam param "area"
    fracpix <- getParam param "fracpix"
    tol <- getParam param "tolerance"
    sc  <- getParam param "scale"
    method  <- getParam param "method" :: IO Int
    alpha <- getParam param "alpha" :: IO Double

    orig <- cam

    inWin w $ do
        clear [DepthBuffer]
        drawImage (gray orig)
        clear [DepthBuffer]
        let (Size h w) = size (gray orig)
            pixarea = h*w*area`div`1000
            redu = Closed . pixelsToPoints (size $ gray orig). douglasPeuckerClosed fracpix
            cs1 = map (redu.fst3) $ contours 100 pixarea th2 True (gray orig)
            cs2 = map (redu.fst3) $ contours 100 pixarea th2 False (gray orig)
            candidates = cs1++cs2
            rawellipses = sortBy (compare `on` (negate.perimeter))
                        . filter (isEllipse tol)
                        $ candidates
            est (Closed ps) = estimateConicRaw ps
            ellipMat = map est rawellipses
            ellipses = map (fst.analyzeEllipse) ellipMat
        pointCoordinates (size $ gray orig)
        lineWidth $= 1
        setColor' Col.yellow
        mapM_ shcont candidates
        setColor' Col.red
        lineWidth $= 3
        mapM_ (shcont . Closed . conicPoints 50) ellipses
        when (length ellipses >= 2) $ do
            let improve = if method == 1 then id else flip improveCirc ellipMat
            let sol = intersectionEllipses (ellipMat!!0) (ellipMat!!1)
                (mbij,mbother) = selectSol (ellipses!!0) (ellipses!!1) sol
            when (isJust mbij && isJust mbother) $ do
                let Just ijr    = mbij
                    ij = improve ijr
                    Just other = mbother
                    [h1,h2] = getHorizs [ij,other]
                lineWidth $= 1
                setColor' Col.blue
                shLine h1
                setColor' Col.yellow
                shLine h2
                pointSize $= 5
                setColor' Col.purple
                renderPrimitive Points $ mapM (vertex.map realPart.t2l) [ij,other]
                setColor' Col.green
                mapM_ shLine $ map (map realPart) $ tangentEllipses (ellipMat!!0) (ellipMat!!1)
                
                let cc = inv (ellipMat!!0) <> (ellipMat!!1)
                    vs = map (fst . fromComplex) . toColumns . snd . eig $ cc
                setColor' Col.white
                renderPrimitive Points (mapM (vertex . toList. inHomog) vs)

                let ccl = (ellipMat!!0) <> inv (ellipMat!!1)
                    vsl = map (fst . fromComplex) . toColumns . snd . eig $ ccl
                mapM_ (shLine.toList) vsl

                let recraw = rectifierFromCircularPoint ij
                             -- rectifierFromManyCircles improve ellipMat
                    (mx,my,_,_,_) = ellipses!!0
                    (mx2,my2,_,_,_) = ellipses!!1
                    [[mx',my'],[mx'2,my'2]] = ht recraw [[mx,my],[mx2,my2]]
--                    okrec = similarFrom2Points [mx',my'] [mx'2,my'2] [0,0] [-0.5, 0] <> recraw
                    okrec = diagl[-1,1,1]<>similarFrom2Points [mx',my'] [mx'2,my'2] [mx,my] [mx2, my2] <> recraw
                    
                    Just cam = cameraFromHomogZ0 Nothing (inv okrec)

                    elliprec = map f ellipMat
                      where f m =  analyzeEllipse $ a <> m <> trans a
                            a = mt okrec
                    g ((x,y,r,_,_),_) = sphere x y (r/2) (r/2)
                cameraView cam (4/3) 0.1 100
                clear [DepthBuffer]
                mapM_ g elliprec
                
                inWin wr $ do
                    --drawImage $ warp 0 sz' (scaling sc <> w) (gray orig)
                    drawImage $ warp (0,0,0) sz' (scaling sc <> okrec ) (rgb orig)
                    --text2D 30 30 $ show $ focalFromHomogZ0 (inv recraw)
                    -- it is also encoded in the circular points
                    text2D 30 30 $ printf "f = %.2f" $ focalFromCircularPoint ij
                    text2D 30 50 $ printf "ang = %.1f" $ abs ((acos $ circularConsistency ij)/degree - 90)


mt m = trans (inv m)
fst3 (a,_,_) = a
t2l (a,b) = [a,b]

shcont = renderPrimitive LineLoop . vertex

----------------------------------------------------------------

isEllipse tol c = (ft-f1)/ft < fromIntegral (tol::Int)/1000 where
    wc = whitenContour c
    f  = fourierPL wc
    f0 = magnitude (f 0)
    f1 = sqrt (magnitude (f (-1)) ^2 + magnitude (f 1) ^2)
    ft = sqrt (norm2Cont wc - f0 ^2)

----------------------------------------------------------------

tangentEllipses c1 c2 = map ((++[1]). t2l) $ intersectionEllipses (inv c1) (inv c2)

--------------------------------------------------------------------

-- hmm, this must be studied in more depth
improveCirc (rx:+ix,ry:+iy) ells = (rx':+ix',ry':+iy') where
    [rx',ix',ry',iy'] = fst $ minimize NMSimplex2 1e-5 300 (replicate 4 0.1) cost [rx,ix,ry,iy]
    cost [rx,ix,ry,iy] = sum $ map (eccentricity.rectif) $ ells
        where rectif e = mt t <> e <> inv t
              t = rectifierFromCircularPoint (rx:+ix,ry:+iy)
    eccentricity con = d1-d2 where (_,_,d1,d2,_) = fst $ analyzeEllipse con

----------------------------------------------------------------------
    
-- | obtain a rectifing homograpy from several conics which are the image of circles 
--rectifierFromManyCircles :: [Mat] -> Maybe Mat
rectifierFromManyCircles f cs = r ijs
  where
    cqs = zip cs (map (fst.analyzeEllipse) cs)
    ijs = catMaybes (pairsWith imagOfCircPt cqs)
    r [] = ident 3
    r xs = rectifierFromCircularPoint (f $ average' xs)
    average xs = (x,y) where [x,y] = toList (head xs)
    average' zs = (x,y)
      where
        pn = meanV . covStr . debug "pn" id . fromRows $ map (fst.fromComplex) zs
        cpn = complex pn
        ds = mean $ debug "ds" id [pnorm PNorm2 (z - cpn) | z <- zs]
        [pnx,pny] = toList pn
        dir = scalar i * complex (scalar ds * unitary (fromList [pny, -pnx]))
        [x,y] = toList (cpn + dir)

----------------------------------------------------------------------

