import basePath from "@salesforce/community/basePath";

export const MEXICO_CITY_TZ = "America/Mexico_City";

export const STATUSES = [
  "Requested",
  "Picked up",
  "In transit",
  "Out for delivery",
  "Delivered",
  "Exception"
];

/** Site-relative URL, e.g. sitePath('/my-shipments') => '/rutacargo/my-shipments'. */
export function sitePath(path) {
  const base = basePath || "";
  return `${base}${path}`;
}

/** BR-06: date-times are shown in Mexico City time. */
export function formatDateTime(value) {
  if (!value) {
    return "—";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "—";
  }
  return new Intl.DateTimeFormat("en-US", {
    timeZone: MEXICO_CITY_TZ,
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  }).format(date);
}

/** Plain dates (yyyy-mm-dd) are calendar days; format them without shifting time zones. */
export function formatDate(value) {
  if (!value) {
    return "—";
  }
  const date = new Date(`${String(value).substring(0, 10)}T12:00:00Z`);
  if (Number.isNaN(date.getTime())) {
    return "—";
  }
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "UTC",
    weekday: "short",
    year: "numeric",
    month: "short",
    day: "numeric"
  }).format(date);
}

export function formatCurrency(value) {
  if (value === null || value === undefined || value === "") {
    return "—";
  }
  return (
    new Intl.NumberFormat("es-MX", {
      style: "currency",
      currency: "MXN"
    }).format(value) + " MXN"
  );
}

export function statusClass(status) {
  const key = status ? status.toLowerCase().replace(/\s+/g, "-") : "not-found";
  return `rc-status rc-status_${key}`;
}

/** Turns Apex / LDS errors into a readable message. */
export function reduceErrors(error) {
  if (!error) {
    return "Something went wrong. Please try again.";
  }
  if (typeof error === "string") {
    return error;
  }
  if (error.body) {
    if (typeof error.body.message === "string" && error.body.message) {
      return error.body.message;
    }
    if (Array.isArray(error.body) && error.body.length) {
      return error.body.map((e) => e.message).join(" ");
    }
    if (error.body.pageErrors && error.body.pageErrors.length) {
      return error.body.pageErrors.map((e) => e.message).join(" ");
    }
  }
  if (error.message) {
    return error.message;
  }
  return "Something went wrong. Please try again.";
}

/** Validates every lightning input inside a template; returns true when all are valid. */
export function validateInputs(
  template,
  selector = "lightning-input, lightning-textarea, lightning-combobox, lightning-radio-group"
) {
  return [...template.querySelectorAll(selector)].reduce((valid, input) => {
    input.reportValidity();
    return valid && input.checkValidity();
  }, true);
}
