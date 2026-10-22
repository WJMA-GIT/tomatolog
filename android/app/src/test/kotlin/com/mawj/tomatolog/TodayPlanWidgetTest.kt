package com.mawj.tomatolog

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TodayPlanWidgetTest {
    @Test
    fun dateRangeIncludesBothBoundariesAndIgnoresTime() {
        assertTrue(todayPlanOccursOn("2026-10-22T00:00:00.000", "2026-10-24T00:00:00.000", "2026-10-22"))
        assertTrue(todayPlanOccursOn("2026-10-22", "2026-10-24", "2026-10-24"))
        assertFalse(todayPlanOccursOn("2026-10-22", "2026-10-24", "2026-10-21"))
        assertFalse(todayPlanOccursOn("2026-10-22", "2026-10-24", "2026-10-25"))
        assertFalse(todayPlanOccursOn("", "", "2026-10-22"))
    }
}
