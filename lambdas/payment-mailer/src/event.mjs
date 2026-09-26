// The message the API sends when a payment reaches its final status. Version 1.
//
// The queue is the boundary between two deployables, so the message is checked
// here rather than trusted: a malformed one fails loudly and lands in the DLQ
// instead of producing a half-empty email.

export const SETTLED_STATUSES = ['APPROVED', 'DECLINED', 'VOIDED', 'ERROR'];

const isString = (value) => typeof value === 'string' && value.length > 0;
const isOptionalString = (value) => value === undefined || typeof value === 'string';
const isAmount = (value) => Number.isInteger(value) && value >= 0;

const problemsIn = (event) => {
  const problems = [];
  const check = (ok, path) => {
    if (!ok) problems.push(path);
  };

  check(event?.type === 'payment.settled', 'type');
  check(event?.version === 1, 'version');
  check(isString(event?.transactionId), 'transactionId');
  check(SETTLED_STATUSES.includes(event?.status), 'status');
  check(isString(event?.customer?.fullName), 'customer.fullName');
  check(isString(event?.customer?.email) && event.customer.email.includes('@'), 'customer.email');

  check(Array.isArray(event?.lines) && event.lines.length > 0, 'lines');
  (Array.isArray(event?.lines) ? event.lines : []).forEach((line, i) => {
    check(isString(line?.name), `lines[${i}].name`);
    check(Number.isInteger(line?.units) && line.units > 0, `lines[${i}].units`);
    check(isAmount(line?.unitPriceInCents), `lines[${i}].unitPriceInCents`);
    check(isAmount(line?.lineTotalInCents), `lines[${i}].lineTotalInCents`);
  });

  for (const field of ['productInCents', 'baseFeeInCents', 'deliveryFeeInCents', 'totalInCents']) {
    check(isAmount(event?.amounts?.[field]), `amounts.${field}`);
  }
  check(isString(event?.amounts?.currency), 'amounts.currency');

  const delivery = event?.delivery;
  for (const field of ['addressLine1', 'city', 'region', 'country']) {
    check(isString(delivery?.[field]), `delivery.${field}`);
  }
  for (const field of ['addressLine2', 'postalCode', 'estimatedDeliveryAt']) {
    check(isOptionalString(delivery?.[field]), `delivery.${field}`);
  }

  return problems;
};

/** Parses an SQS message body into a payment event, or throws naming every bad field. */
export const parsePaymentEvent = (body) => {
  let event;
  try {
    event = JSON.parse(body);
  } catch {
    throw new Error('The message is not JSON');
  }

  const problems = problemsIn(event);
  if (problems.length > 0) {
    throw new Error(`The message is not a payment.settled v1 event: ${problems.join(', ')}`);
  }
  return event;
};
