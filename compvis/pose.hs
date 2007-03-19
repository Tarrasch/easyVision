-- automatic pose from A4 using segments

module Main where

import EasyVision
import System.Environment(getArgs)
import qualified Data.Map as Map
import Graphics.UI.GLUT hiding (Matrix, Size, Point)
import Vision
import Control.Monad(when)
import GSL hiding (size)

main = do
    args <- getArgs

    let opts = Map.fromList $ zip args (tail args)

    let sz = if Map.member "--size" opts
                 then mpSize $ read $ Map.findWithDefault "20" "--size" opts
                 else Size (read $ Map.findWithDefault "480" "--rows" opts)
                           (read $ Map.findWithDefault "640" "--cols" opts)

    (cam,ctrl) <- mplayer (args!!0) sz >>= withPause

    (tb,kc,mc) <- newTrackball

    app <- prepare ()

    o <- createParameters app [("radius",intParam 4 0 10),
                               ("width",realParam 1.5 0 5),
                               ("median",intParam 5 3 5),
                               ("high",intParam 40 0 255),
                               ("low",intParam 20 0 255),
                               ("postproc",intParam 0 0 1),
                               ("minlength",realParam 0.1 0 1),
                               ("maxdis",realParam 0.001 0 0.01)]

    addWindow "image" sz Nothing (const $ kbdcam ctrl) app

    addWindow "3D view" (Size 400 400) Nothing undefined app
    keyboardMouseCallback $= Just (kc (kbdcam ctrl))
    motionCallback $= Just mc
    depthFunc $= Just Less
    textureFilter Texture2D $= ((Nearest, Nothing), Nearest)
    textureFunction $= Decal

    launch app (worker cam o tb)

-----------------------------------------------------------------


worker cam op trackball inWindow _ = do

    radius <- getParam op "radius"
    width  <- getParam op "width"
    median <- getParam op "median"
    high   <- fromIntegral `fmap` (getParam op "high" :: IO Int)
    low    <- fromIntegral `fmap` (getParam op "low" :: IO Int)
    postp  <- getParam op "postproc" :: IO Int
    let pp = if postp == 0 then False else True
    minlen <- getParam op "minlength"
    maxdis <- getParam op "maxdis"

    orig <- cam >>= yuvToGray
    let segs = filter ((>minlen).segmentLength) $ segments radius width median high low pp orig
        polis = segmentsToPolylines maxdis segs
        closed4 = [p | Closed p <- polis, length p == 4]

    inWindow "image" $ do
        drawImage orig

        pointCoordinates (size orig)

        setColor 0 0 1
        lineWidth $= 1
        renderPrimitive Lines $ mapM_ drawSeg segs

        setColor 1 0 0
        lineWidth $= 3
        mapM_ (renderPrimitive LineLoop . (mapM_ vertex)) closed4

        setColor 0 1 0
        pointSize $= 5
        mapM_ (renderPrimitive Points . (mapM_ vertex)) closed4

    inWindow "3D view" $ do
        clear [ColorBuffer, DepthBuffer]
        trackball

        setColor 0 0 1
        lineWidth $= 2
        renderPrimitive LineLoop (mapM_ vertex a4)

        when (length closed4 >0) $ do
            let pts = head closed4
            mapM_ (posib orig) (alter pts)

    return ()

---------------------------------------------------------

a4 = [[   0,    0]
     ,[   0, 2.97]
     ,[2.10, 2.97]
     ,[2.10,    0]
     ]

pl (Point x y) = [x,y]

alter pts = map (rotateList pts) [0 .. 3]

rotateList list n = take (length list) $ drop n $ cycle list

posib orig pts = do
    let h = estimateHomography (map pl pts) a4
        mc = cameraFromHomogZ0 Nothing h
    case mc of
        Nothing -> return ()
        Just cam  -> do
            let ao = autoOrthogonality (Nothing::Maybe (Matrix Double)) h
            when (ao < 0.1) $ do
                imf <- scale8u32f 0 1 orig
                imt <- extractSquare 128 imf
                drawCamera 1 cam (Just imt)

drawSeg s = do
    vertex $ (extreme1 s)
    vertex $ (extreme2 s)

