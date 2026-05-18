using UnityEngine;

// Receives messages from Flutter via flutter_unity_widget
public static class Unity
{
    private static ARRoomCapture _capture;

    public static void Initialize(ARRoomCapture capture)
    {
        _capture = capture;
    }

    // Called by flutter_unity_widget UnityController.postMessage()
    public static void OnMessageFromFlutter(string json)
    {
        _capture?.HandleFlutterMessage(json);
    }

    // Send message to Flutter (uses flutter_unity_widget callback)
    public static void SendMessageToFlutter(string json)
    {
        // flutter_unity_widget listens via UnityMessageManager.Instance.SendMessageToFlutter
        UnityMessageManager.Instance.SendMessageToFlutter(json);
    }
}
