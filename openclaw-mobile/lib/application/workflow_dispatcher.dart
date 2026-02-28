import '../domain/models.dart';

class WorkflowDispatchResult {
  const WorkflowDispatchResult({this.output, this.handled = false});

  final Object? output;
  final bool handled;
}

typedef WorkflowHandler = Future<WorkflowDispatchResult> Function(Event event, Session session);

class WorkflowDispatcher {
  WorkflowDispatcher({Map<String, WorkflowHandler>? handlers}) : _handlers = handlers ?? const {};

  final Map<String, WorkflowHandler> _handlers;

  Future<WorkflowDispatchResult> dispatch(Event event, Session session) async {
    final workflow = event.payload['workflow']?.toString();
    if (workflow == null || workflow.isEmpty) {
      return const WorkflowDispatchResult();
    }

    final handler = _handlers[workflow];
    if (handler == null) {
      return const WorkflowDispatchResult();
    }

    return handler(event, session);
  }
}
