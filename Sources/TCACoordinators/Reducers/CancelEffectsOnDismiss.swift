import ComposableArchitecture
import Foundation

/// Identifier for a particular route within a particular coordinator.
public struct CancellationIdentity<CoordinatorID: Hashable, RouteID: Hashable>: Hashable {
  let coordinatorId: CoordinatorID
  let routeId: RouteID
}

struct CancelEffectsOnDismiss<
  CoordinatorScreensReducer: Reducer,
  CoordinatorReducer: Reducer,
  CoordinatorID: Hashable,
  ScreenAction: CasePathable,
  RouteID: Hashable,
  C: Collection
>: Reducer
  where CoordinatorScreensReducer.State == CoordinatorReducer.State,
  CoordinatorScreensReducer.Action == CoordinatorReducer.Action,
  CoordinatorScreensReducer.Action: CasePathable
{
  let coordinatedScreensReducer: CoordinatorScreensReducer
  let routes: KeyPath<CoordinatorReducer.State, C>
  let routeAction: CaseKeyPath<Action, (id: RouteID, action: ScreenAction)>
  let cancellationId: CoordinatorID?
  let getIdentifier: (C.Element, C.Index) -> RouteID
  let coordinatorReducer: CoordinatorReducer

  var body: some ReducerOf<CoordinatorReducer> {
    if let cancellationId {
      CancelTaggedRouteEffectsOnDismiss(
        coordinatorReducer: CombineReducers {
          TagRouteEffectsForCancellation(
            screenReducer: coordinatedScreensReducer,
            coordinatorId: cancellationId,
            routeAction: routeAction
          )
          coordinatorReducer
        },
        coordinatorId: cancellationId,
        routes: routes,
        getIdentifier: getIdentifier
      )
    } else {
      CombineReducers {
        coordinatorReducer
        coordinatedScreensReducer
      }
    }
  }
}

struct TagRouteEffectsForCancellation<
  ScreenReducer: Reducer,
  CoordinatorID: Hashable,
  RouteID: Hashable,
  RouteAction
>: Reducer
  where ScreenReducer.Action: CasePathable
{
  let screenReducer: ScreenReducer
  let coordinatorId: CoordinatorID
  let routeAction: CaseKeyPath<ScreenReducer.Action, (id: RouteID, action: RouteAction)>

  var body: some ReducerOf<ScreenReducer> {
    Reduce { state, action in
      let effect = screenReducer.reduce(into: &state, action: action)

      if let (id: routeId, _) = action[case: routeAction] {
        let identity = CancellationIdentity(coordinatorId: coordinatorId, routeId: routeId)
        return effect.cancellable(id: identity)
      } else {
        return effect
      }
    }
  }
}

struct CancelTaggedRouteEffectsOnDismiss<
  CoordinatorReducer: Reducer,
  CoordinatorID: Hashable,
  C: Collection,
  RouteID: Hashable
>: Reducer {
  let coordinatorReducer: CoordinatorReducer
  let coordinatorId: CoordinatorID
  let routes: KeyPath<State, C>
  let getIdentifier: (C.Element, C.Index) -> RouteID

  var body: some ReducerOf<CoordinatorReducer> {
    Reduce { state, action in
      let preRoutes = state[keyPath: routes]
      let effect = coordinatorReducer.reduce(into: &state, action: action)
      let postRoutes = state[keyPath: routes]

      var effects: [Effect<Action>] = [effect]

      let preIds = zip(preRoutes, preRoutes.indices).map(getIdentifier)
      let postIds = zip(postRoutes, postRoutes.indices).map(getIdentifier)

      let dismissedIds = Set(preIds).subtracting(postIds)
      for dismissedId in dismissedIds {
        let identity = CancellationIdentity(coordinatorId: coordinatorId, routeId: dismissedId)
        effects.append(Effect<Action>.cancel(id: identity))
      }

      return .merge(effects)
    }
  }
}
