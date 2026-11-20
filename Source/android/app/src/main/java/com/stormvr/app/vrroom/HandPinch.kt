package com.stormvr.app.vrroom

/** Keeps the button state keyed to one hand and to camera samples. */
internal class HandPinch {
    var ratio = 1f
        private set
    var pressed = false
        private set
    var closing = false
        private set

    private var lastSample = 0L
    private var armed = false
    private var closeFrames = 0
    private var openFrames = 0
    private var minimum = 1f
    private var speed = 0f

    fun update(measured: Float, stamp: Long) {
        if (!measured.isFinite()) {
            miss(stamp)
            return
        }
        expire(stamp)
        val previous = ratio
        ratio += (measured.coerceIn(0f, 2f) - ratio) * 0.7f
        if (lastSample != 0L) {
            val dt = ((stamp - lastSample) * 1e-9f).coerceAtLeast(0.001f)
            speed += ((ratio - previous) / dt - speed) * 0.5f
        }
        lastSample = stamp
        if (pressed) {
            minimum = minOf(minimum, ratio)
            val release = (minimum + 0.15f).coerceIn(0.46f, 0.58f)
            openFrames = if (ratio > release) openFrames + 1 else 0
            if (openFrames >= 2 || (openFrames == 1 && speed > 0.4f)) {
                pressed = false
                openFrames = 0
            }
        } else {
            if (measured > 0.46f && ratio > 0.46f) armed = true
            closeFrames = if (armed && ratio < 0.40f) closeFrames + 1 else 0
            if (closeFrames >= 2) {
                pressed = true
                minimum = ratio
                closeFrames = 0
            }
        }
        closing = armed && if (closing) ratio <= 0.9f && speed <= 0.8f else ratio < 0.95f && speed < -0.9f
    }

    fun miss(stamp: Long) {
        closeFrames = 0
        openFrames = 0
        closing = false
        expire(stamp)
    }

    private fun expire(stamp: Long) {
        if (lastSample != 0L && stamp - lastSample >= 120_000_000L) reset()
    }

    fun reset() {
        ratio = 1f
        pressed = false
        closing = false
        lastSample = 0L
        armed = false
        closeFrames = 0
        openFrames = 0
        minimum = 1f
        speed = 0f
    }
}
