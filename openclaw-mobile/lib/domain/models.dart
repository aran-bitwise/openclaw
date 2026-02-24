enum EventType { humanMessage, heartbeat, cron, hook, webhook }

enum QueueState { queued, processing, completed, failed, deadLetter }

abstract class VersionedEntity {
  int get schemaVersion;
  Map<String, dynamic> toJson();
}

class ActiveHoursWindow {
  ActiveHoursWindow({required this.startMinuteOfDay, required this.endMinuteOfDay});

  final int startMinuteOfDay;
  final int endMinuteOfDay;

  factory ActiveHoursWindow.fromJson(Map<String, dynamic> json) => ActiveHoursWindow(
    startMinuteOfDay: json['startMinuteOfDay'] as int,
    endMinuteOfDay: json['endMinuteOfDay'] as int,
  );

  Map<String, dynamic> toJson() => {
    'startMinuteOfDay': startMinuteOfDay,
    'endMinuteOfDay': endMinuteOfDay,
  };
}

class HeartbeatSettings {
  HeartbeatSettings({
    required this.enabled,
    required this.intervalMinutes,
    required this.activeHours,
    required this.promptTemplate,
    this.lastFiredAt,
    this.suppressedUntil,
    this.suppressionToken = 'HEARTBEAT_OK',
    this.suppressionWindowMinutes = 120,
  });

  final bool enabled;
  final int intervalMinutes;
  final ActiveHoursWindow activeHours;
  final String promptTemplate;
  final int? lastFiredAt;
  final int? suppressedUntil;
  final String suppressionToken;
  final int suppressionWindowMinutes;

  factory HeartbeatSettings.disabled() => HeartbeatSettings(
    enabled: false,
    intervalMinutes: 30,
    activeHours: ActiveHoursWindow(startMinuteOfDay: 8 * 60, endMinuteOfDay: 21 * 60),
    promptTemplate: 'Quick status check-in. Reply HEARTBEAT_OK if no action is needed.',
  );

  factory HeartbeatSettings.fromJson(Map<String, dynamic> json) => HeartbeatSettings(
    enabled: json['enabled'] as bool? ?? false,
    intervalMinutes: json['intervalMinutes'] as int? ?? 30,
    activeHours: json['activeHours'] is Map
        ? ActiveHoursWindow.fromJson(Map<String, dynamic>.from(json['activeHours'] as Map))
        : ActiveHoursWindow(startMinuteOfDay: 8 * 60, endMinuteOfDay: 21 * 60),
    promptTemplate:
        json['promptTemplate'] as String? ?? 'Quick status check-in. Reply HEARTBEAT_OK if no action is needed.',
    lastFiredAt: json['lastFiredAt'] as int?,
    suppressedUntil: json['suppressedUntil'] as int?,
    suppressionToken: json['suppressionToken'] as String? ?? 'HEARTBEAT_OK',
    suppressionWindowMinutes: json['suppressionWindowMinutes'] as int? ?? 120,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'intervalMinutes': intervalMinutes,
    'activeHours': activeHours.toJson(),
    'promptTemplate': promptTemplate,
    'lastFiredAt': lastFiredAt,
    'suppressedUntil': suppressedUntil,
    'suppressionToken': suppressionToken,
    'suppressionWindowMinutes': suppressionWindowMinutes,
  };

  HeartbeatSettings copyWith({
    bool? enabled,
    int? intervalMinutes,
    ActiveHoursWindow? activeHours,
    String? promptTemplate,
    int? lastFiredAt,
    int? suppressedUntil,
    String? suppressionToken,
    int? suppressionWindowMinutes,
  }) {
    return HeartbeatSettings(
      enabled: enabled ?? this.enabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      activeHours: activeHours ?? this.activeHours,
      promptTemplate: promptTemplate ?? this.promptTemplate,
      lastFiredAt: lastFiredAt ?? this.lastFiredAt,
      suppressedUntil: suppressedUntil ?? this.suppressedUntil,
      suppressionToken: suppressionToken ?? this.suppressionToken,
      suppressionWindowMinutes: suppressionWindowMinutes ?? this.suppressionWindowMinutes,
    );
  }
}

class AgentProfile implements VersionedEntity {
  AgentProfile({
    required this.id,
    required this.name,
    required this.createdAt,
    HeartbeatSettings? heartbeat,
    this.schemaVersion = 2,
  }) : heartbeat = heartbeat ?? HeartbeatSettings.disabled();

  final String id;
  final String name;
  final int createdAt;
  final HeartbeatSettings heartbeat;
  @override
  final int schemaVersion;

  factory AgentProfile.fromJson(Map<String, dynamic> json) => AgentProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: json['createdAt'] as int,
    heartbeat: json['heartbeat'] is Map
        ? HeartbeatSettings.fromJson(Map<String, dynamic>.from(json['heartbeat'] as Map))
        : HeartbeatSettings.disabled(),
    schemaVersion: (json['schemaVersion'] as int?) ?? 1,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
    'heartbeat': heartbeat.toJson(),
    'schemaVersion': schemaVersion,
  };

  AgentProfile copyWith({String? name, HeartbeatSettings? heartbeat}) {
    return AgentProfile(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      heartbeat: heartbeat ?? this.heartbeat,
      schemaVersion: schemaVersion,
    );
  }
}

class Session implements VersionedEntity {
  Session({required this.id, required this.agentId, required this.channelId, required this.createdAt, this.schemaVersion = 1});

  final String id;
  final String agentId;
  final String channelId;
  final int createdAt;
  @override
  final int schemaVersion;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] as String,
    agentId: json['agentId'] as String,
    channelId: json['channelId'] as String,
    createdAt: json['createdAt'] as int,
    schemaVersion: (json['schemaVersion'] as int?) ?? 1,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'agentId': agentId,
    'channelId': channelId,
    'createdAt': createdAt,
    'schemaVersion': schemaVersion,
  };
}

class Event implements VersionedEntity {
  Event({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.payload,
    required this.idempotencyKey,
    required this.createdAt,
    this.schemaVersion = 1,
  });

  final String id;
  final String sessionId;
  final EventType type;
  final Map<String, dynamic> payload;
  final String idempotencyKey;
  final int createdAt;
  @override
  final int schemaVersion;

  factory Event.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String;
    final normalized = rawType == 'message' ? 'humanMessage' : rawType;
    return Event(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      type: EventType.values.byName(normalized),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      idempotencyKey: json['idempotencyKey'] as String,
      createdAt: json['createdAt'] as int,
      schemaVersion: (json['schemaVersion'] as int?) ?? 1,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'type': type.name,
    'payload': payload,
    'idempotencyKey': idempotencyKey,
    'createdAt': createdAt,
    'schemaVersion': schemaVersion,
  };
}

class MemoryEntry implements VersionedEntity {
  MemoryEntry({required this.id, required this.sessionId, required this.content, required this.createdAt, this.schemaVersion = 1});

  final String id;
  final String sessionId;
  final String content;
  final int createdAt;
  @override
  final int schemaVersion;

  factory MemoryEntry.fromJson(Map<String, dynamic> json) => MemoryEntry(
    id: json['id'] as String,
    sessionId: json['sessionId'] as String,
    content: json['content'] as String,
    createdAt: json['createdAt'] as int,
    schemaVersion: (json['schemaVersion'] as int?) ?? 1,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'content': content,
    'createdAt': createdAt,
    'schemaVersion': schemaVersion,
  };
}

class ToolInvocation implements VersionedEntity {
  ToolInvocation({required this.id, required this.eventId, required this.toolName, required this.status, this.schemaVersion = 1});

  final String id;
  final String eventId;
  final String toolName;
  final String status;
  @override
  final int schemaVersion;

  factory ToolInvocation.fromJson(Map<String, dynamic> json) => ToolInvocation(
    id: json['id'] as String,
    eventId: json['eventId'] as String,
    toolName: json['toolName'] as String,
    status: json['status'] as String,
    schemaVersion: (json['schemaVersion'] as int?) ?? 1,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'eventId': eventId,
    'toolName': toolName,
    'status': status,
    'schemaVersion': schemaVersion,
  };
}

class RunResult implements VersionedEntity {
  RunResult({required this.id, required this.eventId, required this.output, required this.completedAt, this.schemaVersion = 1});

  final String id;
  final String eventId;
  final String output;
  final int completedAt;
  @override
  final int schemaVersion;

  factory RunResult.fromJson(Map<String, dynamic> json) => RunResult(
    id: json['id'] as String,
    eventId: json['eventId'] as String,
    output: json['output'] as String,
    completedAt: json['completedAt'] as int,
    schemaVersion: (json['schemaVersion'] as int?) ?? 1,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'eventId': eventId,
    'output': output,
    'completedAt': completedAt,
    'schemaVersion': schemaVersion,
  };
}

class TimelineItem {
  TimelineItem({required this.event, required this.state});

  final Event event;
  final QueueState state;
}
