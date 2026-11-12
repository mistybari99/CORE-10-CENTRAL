/**
 * GOV002 scoped activity CSV formatter (not an authorization layer).
 * Input MUST come from the signed user's server-side RLS-filtered
 * c10_demo.approval_activity_feed_v1 read-only view, not service_role.
 * No fetch, DOM, secrets, email/SMS or production writes.
 */
export const APPROVAL_ACTIVITY_COLUMNS = Object.freeze([
  "activity_id", "business_id", "request_id", "domain",
  "action_code", "source_key", "source_version",
  "request_maker", "event_actor", "activity_type", "action",
  "severity", "occurred_at", "approval_status",
]);

const CONTROL = /[\u0000-\u001f\u007f\u2028\u2029]/gu;
const FORMULA = /^\s*[=+\-@]/u;

function safeCsvCell(value) {
  let text = value == null ? "" : String(value);
  if (text.length > 4000) throw new Error("csv_cell_too_large");
  // Do not allow embedded newlines to create extra rows/formula prefixes.
  text = text.replace(CONTROL, " ");
  if (FORMULA.test(text)) text = "'" + text;
  return '"' + text.replace(/"/g, '""') + '"';
}

/**
 * Format only one explicitly selected business. This is a secondary
 * accidental-cross-business guard, NEVER a substitute for backend RLS.
 */
export function makeApprovalActivityCsv(rows, { businessId } = {}) {
  if (!Number.isSafeInteger(businessId) || businessId <= 0) {
    throw new Error("export_requires_positive_business_id");
  }
  if (!Array.isArray(rows) || rows.length > 5000) {
    throw new Error("export_rows_invalid_or_over_limit");
  }
  const output = [APPROVAL_ACTIVITY_COLUMNS.map(safeCsvCell).join(",")];
  for (const row of rows) {
    if (!row || typeof row !== "object"
      || !Number.isSafeInteger(Number(row.business_id))
      || Number(row.business_id) !== businessId
      || !/^((approval|exception):[1-9][0-9]*)$/u.test(row.activity_id || "")
      || !Number.isSafeInteger(Number(row.request_id))
      || Number(row.request_id) <= 0) {
      throw new Error("export_row_invalid_or_other_business");
    }
    output.push(APPROVAL_ACTIVITY_COLUMNS.map((key) => safeCsvCell(row[key])).join(","));
  }
  // UTF-8 BOM lets desktop Excel preserve Bangla text; only textual export.
  return "\uFEFF" + output.join("\r\n") + "\r\n";
}
