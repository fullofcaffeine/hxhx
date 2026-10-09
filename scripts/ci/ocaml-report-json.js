/** Independent report-byte encoder for fixtures that alter semantic facts. */
function reportJson(value) {
	if (value === null || typeof value === 'boolean' || typeof value === 'string') return JSON.stringify(value)
	if (typeof value === 'number' && Number.isInteger(value) && value >= -2147483648 && value <= 2147483647) {
		return JSON.stringify(value)
	}
	if (Array.isArray(value)) return '[' + value.map(reportJson).join(',') + ']'
	if (value && Object.getPrototypeOf(value) === Object.prototype) {
		const keys = Object.keys(value).sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)))
		return '{' + keys.map(key => JSON.stringify(key) + ':' + reportJson(value[key])).join(',') + '}'
	}
	throw new Error('Unsupported report JSON value')
}
module.exports = reportJson
