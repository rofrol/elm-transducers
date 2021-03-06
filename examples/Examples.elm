module Main exposing (..)

import Transducer exposing (..)
import Transducer as T exposing ((>>>))
import Transducer.Debug exposing (..)
import Html exposing (Html)
import Set
import Array
import Mouse
import String
import Result


double : Transducer a a r ()
double =
    { init = \reduce r -> ( (), r )
    , step = \xf a ( _, r ) -> ( (), r |> xf a |> xf a )
    , complete = \xf ( _, r ) -> r
    }


generate : a -> Transducer a a r ()
generate extra =
    { init = \reduce r -> ( (), r )
    , step = \xf a ( _, r ) -> ( (), xf a r )
    , complete = \xf ( _, r ) -> xf extra r
    }


take_ n =
    debug "take" <| take n


map_ fn =
    debug "map" <| map fn


filter_ fn =
    debug "filter" <| filter fn


generate_ a =
    debug "generate" <| generate a


double_ =
    debug "double" <| double


combined =
    filter (\x -> x >= 3)
        >>> map toString
        >>> double
        >>> take 3
        >>> generate "999"
        >>> generate "777"
        >>> partition 3


combined_ =
    debug "combined" combined


parseValidInts : Transducer String Int r ( ( ( (), () ), () ), () )
parseValidInts =
    T.map String.toInt
        >>> T.map Result.toMaybe
        >>> T.filter ((/=) Nothing)
        >>> T.map (Maybe.withDefault 0)


show : a -> Html msg
show a =
    Html.text <| toString a


flowDown : List (Html msg) -> Html msg
flowDown children =
    children
        |> List.map (\child -> Html.div [] [ child ])
        |> Html.div []


render e =
    flowDown
        [ e
        , show <| transduceList (take 2) [ "A", "B", "C", "D" ]
        , show <| transduceList (map toString) [ 1, 2, 3, 4 ]
        , show <| transduceList (filter (\x -> x >= 3)) [ 1, 5, 2, 3, 4 ]
        , show <| transduceList (double) [ "A", "X", "B" ]
        , show <| transduceList combined [ 1, 2, 3, 4 ]
        , show <| transduceArray (take 2) (Array.initialize 5 identity)
        , show <| transduceArray (take 2 >>> map toString) (Array.initialize 5 identity)
          --, show <| transduceArray combined (Array.initialize 5 identity)
          --, show <| transduce List.foldr Set.insert (Set.singleton "9") combined [1, 2, 3, 4]
          --, show <| transduce Set.foldr Set.insert Set.empty combined (Set.fromList [8])
        , show <| transduce List.foldr (+) 0 (comp double (generate 100)) [ 1, 2, 3 ]
        , show <| transduce Set.foldr (+) 0 (comp double (generate 100)) (Set.fromList [ 1, 2, 3 ])
        , show <| transduceList parseValidInts [ "123", "-34", "35.0", "SDF", "7" ]
        ]


mt =
    filter (\{ x, y } -> y <= 100)
        >>> map show


main =
    Html.program
        { init = ( Html.text "", Cmd.none )
        , subscriptions = \_ -> Mouse.moves identity
        , update =
            \a _ ->
                ( transduceList mt [ a ]
                    |> Html.div []
                , Cmd.none
                )
        , view = render
        }
