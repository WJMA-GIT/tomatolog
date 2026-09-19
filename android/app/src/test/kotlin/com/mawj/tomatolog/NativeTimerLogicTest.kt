package com.mawj.tomatolog

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NativeTimerLogicTest {
    @Test
    fun burnInMovementStaysVisibleAndReversesAtEdges() {
        assertEquals(320, nextBurnInY(currentY = 200, minY = 0, maxY = 600, moveDown = true))
        assertEquals(480, nextBurnInY(currentY = 600, minY = 0, maxY = 600, moveDown = true))
        assertEquals(120, nextBurnInY(currentY = 0, minY = 0, maxY = 600, moveDown = false))
    }

    @Test
    fun zeroLengthBreaksAreSkippedAndFinalFocusCompletes() {
        val focus = timer(phase = "running", cycle = 1, cycles = 2, group = 1, groups = 2)
        val nextCycle = focus.copy(intervalSeconds = 0).nextStage()
        assertEquals("running", nextCycle?.phase)
        assertEquals(2, nextCycle?.currentCycle)

        val nextGroup = focus.copy(currentCycle = 2, longIntervalSeconds = 0).nextStage()
        assertEquals("running", nextGroup?.phase)
        assertEquals(2, nextGroup?.currentGroup)

        val finalLongBreak = focus.copy(currentCycle = 2, currentGroup = 2).nextStage()
        assertEquals("longInterval", finalLongBreak?.phase)
        assertNull(finalLongBreak?.nextStage())
    }

    private fun timer(
        phase: String,
        cycle: Int,
        cycles: Int,
        group: Int,
        groups: Int,
    ) = TimerNotification(
        category = "测试",
        remainingSeconds = 60,
        totalSeconds = 60,
        color = 0,
        icon = null,
        phase = phase,
        currentCycle = cycle,
        cycleCount = cycles,
        currentGroup = group,
        groupCount = groups,
        focusSeconds = 60,
        intervalSeconds = 10,
        longIntervalSeconds = 20,
    )
}
