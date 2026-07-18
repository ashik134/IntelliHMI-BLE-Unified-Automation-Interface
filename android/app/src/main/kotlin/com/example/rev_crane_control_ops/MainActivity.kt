package com.example.rev_crane_control_ops

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth's Android biometric prompt requires a FragmentActivity host —
// FlutterFragmentActivity extends FlutterActivity and adds that, so this is
// a drop-in replacement with no other behavior change.
class MainActivity : FlutterFragmentActivity()
