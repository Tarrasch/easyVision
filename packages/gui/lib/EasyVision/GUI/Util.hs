-----------------------------------------------------------------------------
{- |
Module      :  EasyVision.GUI.Util
Copyright   :  (c) Alberto Ruiz 2012
License     :  GPL

Maintainer  :  Alberto Ruiz (aruiz at um dot es)
Stability   :  provisional

common interfaces

-}
-----------------------------------------------------------------------------

module EasyVision.GUI.Util (
    observe,
    sMonitor,
    browser,
    editor,
    updateItem,
    camera
) where

import Graphics.UI.GLUT hiding (Point,Size,color)
import EasyVision.GUI.Types
import EasyVision.GUI.Interface
import Control.Arrow((***))
import ImagProc
import ImagProc.Util(findSize,readFolderMP,readFolderIM,getCam,(~>))
import Util.Misc(replaceAt)
import Util.Options
import Control.Concurrent(threadDelay)
import Data.Colour.Names

editor :: [Command (Int,[x]) (Int,[x])] -> [Command (Int,[x]) (IO())]
       -> String -> [x] -> (Int -> x -> Drawing) -> IO (EVWindow (Int,[x]))
editor upds acts name xs drw = standalone (Size 300 300) name (0,xs) (upds ++ move) acts f
  where
    f (k,xs) | null xs = text (Point 0 0) "empty list!"
             | otherwise = drw j (xs !! j)
                 where
                   j = k `mod` (length xs)   
    move = g2 [((MouseButton WheelUp,   Down, modif), (+1))
              ,((SpecialKey  KeyUp,     Down, modif), (+1))
              ,((MouseButton WheelDown, Down, modif), pred)
              ,((SpecialKey  KeyDown,   Down, modif), pred)]
    g2 = map (id *** const.const.(***id))

--    g1 = map (id *** const.const.(snd.))
--    g3 = map (id *** const.const)


--updateItem :: key -> (a -> a) -> (key, roi -> pt -> (Int, [a]) -> (Int, [a]))
updateItem key f = (key, \roi pt (k,xs) -> (k, replaceAt [k] [f roi pt (xs!!k)] xs))

--------------------------------------------------------------------------------

browser :: String -> [x] -> (Int -> x -> Drawing) -> IO (EVWindow (Int,[x]))
browser = editor [] [] 

--------------------------------------------------------------------------------

sMonitor :: String -> (WinRegion -> b -> [Drawing]) -> VC b b
sMonitor name f = interface (Size 240 360) name 0 (const.const.return $ ()) (c2 acts) [] (const (,)) g
  where
    g roi k x = r !! j
      where
        r = f roi x
        j = k `mod` length r
    acts = [((MouseButton WheelUp,   Down, modif), (+1))
           ,((SpecialKey  KeyUp,     Down, modif), (+1))
           ,((MouseButton WheelDown, Down, modif), pred)
           ,((SpecialKey  KeyDown,   Down, modif), pred)]
    c2 = Prelude.map (id *** const.const)

--------------------------------------------------------------------------------

observe :: Renderable x => String -> (b -> x) -> VC b b
observe name f = interface (Size 240 360) name () (const.const.return $ ()) [] [] (const (,)) (const.const $ Draw . f)

--------------------------------------------------------------------------------
{-
cameraFolder = do
    path <- optionString "--photos" "."
    sz <- findSize
    imgs <- readFolder path (Just sz)
    let disp rk = do
           k <- get rk  
           drawImage (imgs!!k)
    w <- evWindow 0 ("Folder: "++path) (mpSize 10) (Just disp) (mouseGen (cfacts (length imgs -1)) kbdQuit)               
    return $ do
        k <- getW w    
        return (channels $ imgs!!k)

cfacts n = [((MouseButton WheelUp,   Down, modif), \_ k -> min (k+1) n)
           ,((SpecialKey  KeyUp,     Down, modif), \_ k -> min (k+1) n)
           ,((MouseButton WheelDown, Down, modif), \_ k -> max (k-1) 0)
           ,((SpecialKey  KeyDown,   Down, modif), \_ k -> max (k-1) 0)]

-}


-- | returns the camera 0. (It also admits --photos=path/to/folder/ with images, and --variable-size, to read images of
-- different arbitrary sizes.)
camera :: IO (IO Channels)
camera = do
    f <- hasValue "--photos"
    g <- getFlag "--variable-size"
    if f then if g then cameraFolderIM else cameraFolderMP
         else cameraV

cameraV = findSize >>= getCam 0 ~> channels


cameraFolderIM = dummy >>= camG r
  where
    r p _ = readFolderIM p

cameraFolderMP = dummy >>= camG readFolderMP

  
camG readf c = do
    path <- optionString "--photos" "."
    sz <- findSize
    imgs <- readf path (Just sz)
    interface (Size 240 320) "photos" (0,imgs) ft (keys imgs) [] r sh c
  where
    keys xs = acts (length xs -1)
    acts n = [ ((MouseButton WheelUp,   Down, modif), \_ _ (k,xs) -> (min (k+1) n,xs))
             , ((SpecialKey  KeyUp,     Down, modif), \_ _ (k,xs) -> (min (k+1) n,xs))
             , ((MouseButton WheelDown, Down, modif), \_ _ (k,xs) -> (max (k-1) 0,xs))
             , ((SpecialKey  KeyDown,   Down, modif), \_ _ (k,xs) -> (max (k-1) 0,xs))]
    r _ (k,xs) _ = ((k,xs), fst $ xs!!k)
    sh _ (k,xs) x = Draw [Draw (rgb x), info (k,xs) ]
    ft w _ = evPrefSize w $= Just (Size 240 320)
    info (k,xs) = Draw [color black, textF Helvetica12 (Point 0.9 0.6)
                        (show w ++ "x" ++ show h ++ " " ++snd ( xs!!k)) ]
      where
        Size h w = size (grayscale $ fst $ xs!!k)

dummy :: IO (IO ())
dummy = return (threadDelay 100000 >> return ())

