enum ConnectionMode {
  idle,
  connecting,
  pendingIncomingRequest,
  controller,
  receiver,
}

enum ControlState {
  active,
  paused,
}

/// The connection mode selected by the user for a session.
enum SessionMode {
  controlOnly,
  viewOnly,
  viewAndControl;

  String get label {
    switch (this) {
      case SessionMode.controlOnly:
        return 'Control Only';
      case SessionMode.viewOnly:
        return 'View Only';
      case SessionMode.viewAndControl:
        return 'View & Control';
    }
  }

  String get description {
    switch (this) {
      case SessionMode.controlOnly:
        return 'Control the remote device using the keyboard and mouse, without screen streaming.';
      case SessionMode.viewOnly:
        return "View the remote device's screen without controlling its keyboard or mouse.";
      case SessionMode.viewAndControl:
        return 'View the remote screen and control its keyboard and mouse simultaneously.';
    }
  }

  bool get allowsControl => this == SessionMode.controlOnly || this == SessionMode.viewAndControl;
  bool get allowsView => this == SessionMode.viewOnly || this == SessionMode.viewAndControl;

  String toWireString() {
    switch (this) {
      case SessionMode.controlOnly:
        return 'control_only';
      case SessionMode.viewOnly:
        return 'view_only';
      case SessionMode.viewAndControl:
        return 'view_and_control';
    }
  }

  static SessionMode fromWireString(String? str) {
    switch (str) {
      case 'view_only':
        return SessionMode.viewOnly;
      case 'view_and_control':
        return SessionMode.viewAndControl;
      case 'control_only':
      default:
        return SessionMode.controlOnly;
    }
  }
}
