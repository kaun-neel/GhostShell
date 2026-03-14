module Main where

import System.IO
import System.Environment
import System.Directory
import System.FilePath ((</>))
import System.FilePath.Posix (splitSearchPath)
import System.Process
import System.Exit (exitSuccess, exitWith, ExitCode(..))
import Control.Exception
import Control.Monad (filterM)
import Data.List (isPrefixOf, sort, intercalate, transpose)

data Mode = Normal | Single | Double

builtins :: [String]
builtins = ["echo","exit","type","pwd","cd"]

main :: IO ()
main = do
    hSetBuffering stdin NoBuffering
    hSetBuffering stdout NoBuffering
    hSetEcho stdin False
    repl

-- REPL -- 
repl :: IO ()
repl = do
    putStr "$ "
    hFlush stdout
    line <- readLine "" False
    putStrLn ""
    handleCommand line
    repl

readLine :: String -> Bool -> IO String
readLine buf lastWasTab = do
    c <- hGetChar stdin
    case c of

        '\n' -> return buf

        '\r' -> return buf

        '\t' -> do
            matches <- getMatches buf
            case matches of
                [] -> do
                    putChar '\x07'
                    hFlush stdout
                    readLine buf False
                _ -> do
                    let lcp = longestCommonPrefix matches
                    if length matches == 1 then do
                        let newBuf = lcp ++ " "
                        let lineLen = length newBuf + 2
                        putStr ("\r" ++ replicate lineLen ' ' ++ "\r$ " ++ newBuf)
                        hFlush stdout
                        readLine newBuf False
                    else if lcp /= buf then do
                        let lineLen = length lcp + 2
                        putStr ("\r" ++ replicate lineLen ' ' ++ "\r$ " ++ lcp)
                        hFlush stdout
                        readLine lcp False
                    else do
                        if not lastWasTab
                            then do
                                putChar '\x07'
                                hFlush stdout
                                readLine buf True
                            else do
                                let sorted = sort matches
                                putStrLn ""
                                putStrLn (intercalate "  " sorted)
                                putStr ("$ " ++ buf)
                                hFlush stdout
                                readLine buf False

        '\DEL' ->
            if null buf
                then readLine buf False
                else do
                    putStr "\b \b"
                    hFlush stdout
                    readLine (init buf) False

        c' | c' < ' ' -> readLine buf False

        _ -> do
            putChar c
            hFlush stdout
            readLine (buf ++ [c]) False


longestCommonPrefix :: [String] -> String
longestCommonPrefix []     = ""
longestCommonPrefix [x]    = x
longestCommonPrefix (x:xs) = foldl commonPrefix x xs
  where
    commonPrefix a b = map fst $ takeWhile (uncurry (==)) $ zip a b

getMatches :: String -> IO [String]
getMatches buf = do
    let builtinMatches = filter (buf `isPrefixOf`) builtins
    case builtinMatches of
        [] -> do
            pathExes <- getPathExecutables
            return (filter (buf `isPrefixOf`) pathExes)
        _  -> return builtinMatches

getPathExecutables :: IO [String]
getPathExecutables = do
    pathEnv <- getEnv "PATH" `catch` ioErrorHandler ""
    let dirs = splitSearchPath pathEnv
    exes <- mapM exesInDir dirs
    return (concat exes)
  where
    ioErrorHandler :: a -> IOError -> IO a
    ioErrorHandler def _ = return def

    exesInDir dir = do
        exists <- doesDirectoryExist dir
        if not exists
            then return []
            else do
                files <- listDirectory dir `catch` ioErrorHandler []
                filterM (\f -> isExe (dir </> f)) files

    isExe path = do
        exists <- doesFileExist path
        if not exists
            then return False
            else do
                perms <- getPermissions path `catch` ioErrorHandler emptyPermissions
                return (executable perms)

handleCommand :: String -> IO ()
handleCommand line = do
    let parts = parseArgs line
    let (cmdParts, outFile, errFile) = parseRedirect parts

    case errFile of
        Just (f,append) -> do
            let mode = if append then AppendMode else WriteMode
            h <- openFile f mode
            hClose h
        Nothing -> return ()

    if null cmdParts then return () else do
        let cmd  = head cmdParts
        let args = tail cmdParts

        case cmd of
            "exit" -> do
                hFlush stdout
                hFlush stderr
                case args of
                    (code:_) -> case reads code of
                        [(n,"")] -> exitWith (if n == 0 then ExitSuccess else ExitFailure n)
                        _        -> exitSuccess
                    [] -> exitSuccess

            "echo" -> writeStdout outFile (unwords args)

            "pwd" -> do
                dir <- getCurrentDirectory
                writeStdout outFile dir

            "cd" -> runCd args

            "type" -> do
                out <- runType args
                writeStdout outFile out

            _ -> runExternal cmd args outFile errFile

writeStdout :: Maybe (FilePath,Bool) -> String -> IO ()
writeStdout Nothing txt = putStrLn txt
writeStdout (Just (file,append)) txt = do
    let mode = if append then AppendMode else WriteMode
    h <- openFile file mode
    hPutStrLn h txt
    hClose h

-- cd builtin --

runCd :: [String] -> IO ()
runCd [] = return ()
runCd (dir:_) = do
    target <- if dir == "~" then getEnv "HOME" else return dir
    result <- try (setCurrentDirectory target) :: IO (Either IOError ())
    case result of
        Left _  -> putStrLn ("cd: " ++ dir ++ ": No such file or directory")
        Right _ -> return ()

-- type builtin --

runType :: [String] -> IO String
runType [] = return ""
runType (cmd:_) =
    if cmd `elem` builtins
        then return (cmd ++ " is a shell builtin")
    else do
        path <- getEnv "PATH"
        res <- findExecutableInPath cmd (splitSearchPath path)
        case res of
            Just p  -> return (cmd ++ " is " ++ p)
            Nothing -> return (cmd ++ ": not found")

runExternal :: String -> [String] -> Maybe (FilePath,Bool) -> Maybe (FilePath,Bool) -> IO ()
runExternal cmd args outF errF = do
    path <- getEnv "PATH"
    res <- findExecutableInPath cmd (splitSearchPath path)

    case res of
        Nothing -> putStrLn (cmd ++ ": command not found")

        Just _ -> do

            outHandle <- case outF of
                Nothing -> return Nothing
                Just (f,append) -> do
                    let mode = if append then AppendMode else WriteMode
                    Just <$> openFile f mode

            errHandle <- case errF of
                Nothing -> return Nothing
                Just (f,append) -> do
                    let mode = if append then AppendMode else WriteMode
                    Just <$> openFile f mode

            (_,_,_,ph) <- createProcess
                (proc cmd args)
                { std_out = maybe Inherit UseHandle outHandle
                , std_err = maybe Inherit UseHandle errHandle
                }

            _ <- waitForProcess ph

            maybe (return ()) hClose outHandle
            maybe (return ()) hClose errHandle

-- PATH search --

findExecutableInPath :: String -> [FilePath] -> IO (Maybe FilePath)
findExecutableInPath _ [] = return Nothing
findExecutableInPath cmd (d:ds) = do
    let p = d </> cmd
    exists <- doesFileExist p
    if not exists
        then findExecutableInPath cmd ds
    else do
        perms <- getPermissions p
        if executable perms
            then return (Just p)
            else findExecutableInPath cmd ds

parseRedirect :: [String] -> ([String], Maybe (FilePath,Bool), Maybe (FilePath,Bool))
parseRedirect xs = go xs [] Nothing Nothing
  where
    go [] cmd out err = (reverse cmd, out, err)

    go (">":f:rest) cmd _ err = go rest cmd (Just (f,False)) err
    go ("1>":f:rest) cmd _ err = go rest cmd (Just (f,False)) err

    go (">>":f:rest) cmd _ err = go rest cmd (Just (f,True)) err
    go ("1>>":f:rest) cmd _ err = go rest cmd (Just (f,True)) err

    go ("2>":f:rest) cmd out _ = go rest cmd out (Just (f,False))
    go ("2>>":f:rest) cmd out _ = go rest cmd out (Just (f,True))

    go (x:rest) cmd out err = go rest (x:cmd) out err

parseArgs :: String -> [String]
parseArgs input = reverse (go input Normal "" [])
  where
    go [] _ current acc
        | null current = acc
        | otherwise = current : acc

    go ('\\':c:cs) Normal current acc =
        go cs Normal (current ++ [c]) acc

    go (c:cs) mode current acc =
        case mode of

            Normal
                | c == '\'' -> go cs Single current acc
                | c == '"'  -> go cs Double current acc
                | c == ' '  ->
                    if null current
                        then go cs Normal "" acc
                        else go cs Normal "" (current:acc)
                | otherwise ->
                    go cs Normal (current ++ [c]) acc

            Single
                | c == '\'' -> go cs Normal current acc
                | otherwise -> go cs Single (current ++ [c]) acc

            Double
                | c == '"' ->
                    go cs Normal current acc

                | c == '\\', not (null cs), head cs == '"' ->
                    go (tail cs) Double (current ++ ['"']) acc

                | c == '\\', not (null cs), head cs == '\\' ->
                    go (tail cs) Double (current ++ ['\\']) acc

                | c == '\\', not (null cs) ->
                    go cs Double (current ++ ['\\', head cs]) acc

                | otherwise ->
                    go cs Double (current ++ [c]) acc