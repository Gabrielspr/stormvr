package com.stormvr.app.vrroom

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HandPinchTest {
    @Test fun losingOneHandReleasesItIndependently() {
        val left = HandPinch()
        val right = HandPinch()
        for (hand in listOf(left, right)) {
            hand.update(0.8f, at(1))
            hand.update(0.05f, at(34))
            hand.update(0.05f, at(67))
            assertTrue(hand.pressed)
        }
        left.miss(at(130))
        right.update(0.05f, at(130))
        assertTrue(left.pressed)
        left.miss(at(190))
        right.update(0.05f, at(190))
        assertFalse(left.pressed)
        assertTrue(right.pressed)
    }

    @Test fun closedHandReturningToFrameMustOpenBeforeItCanPress() {
        val hand = HandPinch()
        hand.update(0.05f, at(1))
        hand.update(0.05f, at(34))
        hand.update(0.05f, at(67))
        assertFalse(hand.pressed)
        hand.update(0.8f, at(100))
        hand.update(0.05f, at(133))
        assertFalse(hand.pressed)
        hand.update(0.05f, at(166))
        assertTrue(hand.pressed)
    }

    @Test fun occlusionBreaksClosingConfirmation() {
        val hand = HandPinch()
        hand.update(0.8f, at(1))
        hand.update(0.05f, at(34))
        hand.miss(at(67))
        hand.update(0.05f, at(100))
        assertFalse(hand.pressed)
        hand.update(0.05f, at(133))
        assertTrue(hand.pressed)
        hand.update(0.9f, at(166))
        assertFalse(hand.pressed)
    }

    private fun at(ms: Long): Long = ms * 1_000_000
}
