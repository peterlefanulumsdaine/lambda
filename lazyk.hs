import Data.Char
import System.Console.Readline
import Text.ParserCombinators.Parsec

import Debug.Trace

data Term = Leaf String | App Term Term

instance Show Term where
  show (Leaf s)  = s
  show (App l r) = show l ++ showR r where
    showR t@(App _ _) = "(" ++ show t ++ ")"
    showR t = show t

instance Eq Term where
  Leaf s  == Leaf t  = s == t
  App a b == App c d = a == c && b == d
  _       == _       = False

ccexpr :: Parser Term
ccexpr = do
  xs <- many expr
  pure $ case xs of
    [] -> Leaf "I"
    _  -> foldl1 App xs

expr = const (Leaf "I") <$> char 'i' <|> expr'

iotaexpr = const (Leaf "i") <$> char 'i' <|> expr'

expr' = const (Leaf "S") <$> char 's'
  <|> const (Leaf "K") <$> char 'k'
  <|> jotRev . reverse <$> many1 (oneOf "01")
  <|> Leaf . pure <$> letter
  <|> between (char '(') (char ')') ccexpr
  <|> (char '`' >> App <$> expr <*> expr)
  <|> (char '*' >> App <$> iotaexpr <*> iotaexpr)

jotRev []       = Leaf "I"
jotRev ('0':js) = App (App (jotRev js) $ Leaf "S") (Leaf "K")
jotRev ('1':js) = App (Leaf "S") (App (Leaf "K") $ jotRev js)

data Top = Super String [String] Term | Run Term

top :: Parser Top
top = try super <|> Run <$> ccexpr

super = do
  name <- pure <$> letter
  args <- (pure <$>) <$> many letter
  char '='
  rhs <- ccexpr
  pure $ Super name args rhs

main = repl []

eval env t = f t [] where
  f (App m n) stack = f m (n:stack)
  f (Leaf s) stack | Just t <- lookup s env = f t stack
  f (Leaf "I") (n:stack) = f n stack
  f (Leaf "K") [x] = App (Leaf "K") x
  f (Leaf "K") (x:_:stack) = f x stack
  f (Leaf "S") [x] = App (Leaf "S") x
  f (Leaf "S") [x, y] = App (App (Leaf "S") x) y
  f (Leaf "S") (x:y:z:stack) = f (rec (App x z)) $ rec (App y z):stack
  f (Leaf "i") (x:stack) = f (rec $ App (App x $ Leaf "S") $ Leaf "K") stack
  f t@(Leaf _) stack = foldl App t stack
  rec = eval env

norm env term = case eval env term of
  Leaf t  -> Leaf t
  App m n -> App (rec m) (rec n)
  where rec = norm env

simpleBracketAbs args rhs = f (reverse args) rhs where
  f [] t = t
  f (x:xs) (Leaf n)  | x == n    = f xs $ Leaf "I" 
                     | otherwise = f xs $ App (Leaf "K") (Leaf n)
  f (x:xs) (App m n)             = f xs $ App (App (Leaf "S") (f [x] m)) (f [x] n)

bracketAbs args rhs = f (reverse args) rhs where
  f [] t = t
  f (x:xs) t = f xs $ case t of
    App (App (Leaf "S") (Leaf "K")) _    -> App (Leaf "S") (Leaf "K")
    m | m `lacks` x                      -> App (Leaf "K") m
    Leaf n | x == n                      -> Leaf "I" 
    App m (Leaf n) | n == x, m `lacks` x -> m
    App (App (Leaf n0) m) (Leaf n1) | n0 == x, n1 == x ->
      f [x] $ App (App (App (App (Leaf "S") (Leaf "S")) (Leaf "K")) (Leaf x)) m
    App m (App n l) | isComb m, isComb n -> f [x] $ App (App (App (Leaf "S") $ f [x] m) n) l
    App (App m n) l | isComb m, isComb l -> f [x] $ App (App (App (Leaf "S") m) $ f [x] l) n
    App (App m l0) (App n l1) | l0 == l1, isComb m, isComb n ->
      f [x] $ App (App (App (Leaf "S") m) n) l0
    App m n                              -> App (App (Leaf "S") (f [x] m)) (f [x] n)

  isComb (Leaf m)  = m `notElem` args
  isComb (App m n) = isComb m && isComb n

lacks (Leaf m)  s = m /= s
lacks (App m n) s = lacks m s && lacks n s

repl env = do
  ms <- readline "> "
  case ms of
    Nothing -> putStrLn ""
    Just s  -> do
      addHistory s
      case parse top "" s of
        Left err  -> do
          putStrLn $ "parse error: " ++ show err
          repl env
        Right sup@(Super s args rhs) -> do
          let t = bracketAbs args rhs
          putStrLn $ s ++ "=" ++ show t
          repl ((s, t):env)
        Right (Run term) -> do
          print $ norm env term
          repl env
