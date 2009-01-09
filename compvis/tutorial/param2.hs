import EasyVision
import Graphics.UI.GLUT
import Control.Arrow

camera = prepare >> findSize >>= getCam 0 ~> (channels >>> gray >>> float)
observe winname f = monitor winname (mpSize 20) f
run = (>> return ()) >>> launch

data Param = Param { sigma :: Float, rad :: Int, thres :: Float }

main =   camera >>= userParam
     ~>  fst &&& corners
     >>= observe "corners" sh >>= run

corners (x,p) =  gaussS (sigma p)
             >>> gradients
             >>> hessian
             >>> fixscale
             >>> thresholdVal32f (thres p) 0 IppCmpLess
             >>> localMax (rad p)
             >>> getPoints32f 100
              $  x

fixscale im = (1/mn) .* im
    where (mn,_) = EasyVision.minmax im

sh (im, pts) = do
    drawImage im
    pointSize $= 5; setColor 1 0 0
    renderPrimitive Points $ mapM_ vertex pts

userParam cam = do
    o <- createParameters [("sigma",realParam 3 0 20),
                           ("rad"  ,intParam  4 1 25),
                           ("thres",realParam 0.6 0 1)]
    return $ do
        x <- cam
        s <- getParam o "sigma"
        r <- getParam o "rad"
        t <- getParam o "thres"
        return (x, Param {sigma = s, rad = r, thres = t})
