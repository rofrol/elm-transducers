module Transducer exposing (..)

{-| A transducer is a composable way of processing a series of values.
Many basic transducers correspond to functions you may be familiar with for
processing `List`s.

    import Maybe
    import String
    import Transducer exposing (..)

    parseValidInts =
        map String.toInt
        >>> map toMaybe
        >>> filter ((/=) Nothing)
        >>> map (Maybe.withDefault 0)

    exampleList : List Int
    exampleList = transduceList parseValidInts ["123", "-34", "35.0", "SDF", "7"]

# Definitions
@docs Reducer, Transducer, Fold

# Common transducers
@docs map, filter, take, drop

# More transducers
@docs concatMap, dedupe, partition

# Composing transducers
@docs (>>>), comp

# Applying transducers
@docs transduce, transduceList, transduceSet, transduceArray
-}

import Set exposing (Set)
import Array exposing (Array)


{-| A reducer is a function taking an input and a value and produces a new value.

    List.foldl : Reducer a b -> b -> List a -> b
-}
type alias Reducer input result =
    input -> result -> result


{-| A transducer an `init` value for it's internal state, a `step` function that
transforms a Reducer into a Reducer of a new type, and a `complete` function that
transforms a Reducer into a function collapsing the internal state.

When defining transducers, the type parameter `r` should be left free.
-}
type alias Transducer a b r state =
    { init : Reducer b r -> r -> ( state, r )
    , step : Reducer b r -> Reducer a ( state, r )
    , complete : Reducer b r -> ( state, r ) -> r
    }


{-| A fold is function that takes a Reducer, an initial value, and input source,
and returns a final value.
-}
type alias Fold input result source =
    Reducer input result -> result -> source -> result


{-| Apply a function to every value.

    transduceList (map sqrt) [1,4,9] == [1,2,3]
-}
map : (a -> b) -> Transducer a b r ()
map f =
    { init = \reduce r -> ( (), r )
    , step = \reduce input ( _, value ) -> ( (), reduce (f input) value )
    , complete = \reduce ( _, value ) -> value
    }


{-| Keep only values that satisfy the predicate.

    transduceList (filter isEven) [1..6] == [2,4,6]
-}
filter : (a -> Bool) -> Transducer a a r ()
filter f =
    { init = \reduce r -> ( (), r )
    , step =
        \reduce input ( _, r ) ->
            if (f input) then
                ( (), reduce input r )
            else
                ( (), r )
    , complete = \reduce ( _, r ) -> r
    }


{-| Map a given function onto a list and flatten the results.

    transduceList (concatMap (\x -> [x,x+10])) [1,2] == [1,10,2,20]
-}
concatMap : (a -> List b) -> Transducer a b r ()
concatMap f =
    { init = \reduce r -> ( (), r )
    , step = \reduce input ( _, r ) -> ( (), List.foldl reduce r (f input) )
    , complete = \reduce ( _, r ) -> r
    }


{-| Take the first *n* values.

    transduceList (take 2) [1,2,3,4] == [1,2]
-}
take : Int -> Transducer a a r Int
take n =
    { init = \reduce r -> ( n, r )
    , step =
        \reduce input ( i, r ) ->
            if (i > 0) then
                ( i - 1, reduce input r )
            else
                ( 0, r )
    , complete = \reduce ( i, r ) -> r
    }


{-| Drop the first *n* values.

    transduceList (drop 2) [1,2,3,4] == [3,4]
-}
drop : Int -> Transducer a a r Int
drop n =
    { init = \reduce r -> ( n, r )
    , step =
        \reduce a ( i, r ) ->
            if (i > 0) then
                ( i - 1, r )
            else
                ( 0, reduce a r )
    , complete = \reduce ( i, r ) -> r
    }


{-| Drop values that repeat the previous value.

    transduceList dedupe [1,1,2,2,1] == [1,2,1]
-}
dedupe : Transducer a a r (Maybe a)
dedupe =
    { init = \reduce r -> ( Nothing, r )
    , step =
        \reduce input ( s, r ) ->
            if (Just input == s) then
                ( s, r )
            else
                ( Just input, reduce input r )
    , complete = \reduce ( s, r ) -> r
    }


{-| Group a series of values into Lists of size n.

    transduceList (partition 2) [1,2,3,4,5] == [[1,2],[3,4],[5]]
-}
partition : Int -> Transducer a (List a) r ( Int, List a )
partition n =
    { init = \reduce r -> ( ( n, [] ), r )
    , step =
        \reduce input ( ( i, hold ), r ) ->
            if (i > 0) then
                ( ( i - 1, input :: hold ), r )
            else
                ( ( n, [ input ] ), reduce hold r )
    , complete = \reduce ( ( i, hold ), r ) -> reduce hold r
    }


{-| An alias for (>>>).
-}
comp : Transducer a b ( s2, r ) s1 -> Transducer b c r s2 -> Transducer a c r ( s1, s2 )
comp t1 t2 =
    { init =
        \reduce r ->
            (t2.init reduce r)
                |> t1.init (t2.step reduce)
                |> \( s1, ( s2, rr ) ) -> ( ( s1, s2 ), rr )
    , step =
        \reduce input ( ( s1, s2 ), r ) ->
            (t1.step (t2.step reduce)) input ( s1, ( s2, r ) )
                |> \( ss1_, ( ss2_, rr_ ) ) -> ( ( ss1_, ss2_ ), rr_ )
    , complete =
        \reduce ( ( s1, s2 ), r ) ->
            (t1.complete (t2.step reduce)) ( s1, ( s2, r ) )
                |> t2.complete reduce
    }


{-| Transducer composition
-}
(>>>) : Transducer a b ( s2, r ) s1 -> Transducer b c r s2 -> Transducer a c r ( s1, s2 )
(>>>) =
    comp


{-| Apply a transducer.
-}
transduce : Fold a ( s, r ) x -> Reducer b r -> r -> Transducer a b r s -> x -> r
transduce fold reduce init t source =
    fold (t.step reduce) (t.init reduce init) source
        |> t.complete reduce


{-| Apply a Transducer to a List, producing a List.

    transduceList t xs == transduce List.foldr (::) [] t xs
-}
transduceList : Transducer a b (List b) s -> List a -> List b
transduceList =
    transduce List.foldr (::) []


{-| Apply a Transducer to a Set, producing a Set.

    transduceSet t xs = transduce Set.foldr Set.insert Set.empty t xs
-}
transduceSet : Transducer comparable comparable_ (Set comparable__) s -> Set comparable -> Set comparable__
transduceSet =
    transduce Set.foldr Set.insert Set.empty


{-| Apply a Transducer to an Array, producing an Array.

    transduceArray t xs = transduce Array.foldl Array.push Array.empty t xs
-}
transduceArray : Transducer a b (Array b) s -> Array a -> Array b
transduceArray =
    transduce Array.foldl Array.push Array.empty
