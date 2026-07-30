'use strict'

const crypto = require('crypto')

/**
 * Recomputes the digest that binds a lowering report's loop targets, transfer
 * decisions, and catch chains together.
 *
 * Normal corruption tests should leave the old digest in place so inspection
 * stops at the report-integrity error. A focused semantic test calls this only
 * after deliberately changing one field, allowing inspection to continue to
 * the field-specific validator that the test is meant to exercise.
 */
function resealControlRevision(report) {
	const canonicalControls = JSON.stringify({
		catchChains: report.controlCatches,
		targets: report.controlTargets,
		decisions: report.controls
	})
	report.controlRevision = `sha256:${crypto.createHash('sha256').update(canonicalControls).digest('hex')}`
	return report.controlRevision
}

module.exports = {
	resealControlRevision
}
