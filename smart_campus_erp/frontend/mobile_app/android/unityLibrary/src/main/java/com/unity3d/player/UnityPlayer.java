package com.unity3d.player;

import android.app.Activity;
import android.content.Context;
import android.widget.FrameLayout;

public class UnityPlayer extends FrameLayout {
    public static Activity currentActivity;

    public UnityPlayer(Context context) {
        super(context);
    }

    public UnityPlayer(Context context, IUnityPlayerLifecycleEvents listener) {
        super(context);
    }

    public void displayChanged(int i, int j) {}
    public void windowFocusChanged(boolean hasFocus) {}
    public void resume() {}
    public void pause() {}
    public void destroy() {}
    public static void UnitySendMessage(String gameObject, String methodName, String message) {}
    public void quit() {}
    public void unload() {}
    public void lowMemory() {}
}
