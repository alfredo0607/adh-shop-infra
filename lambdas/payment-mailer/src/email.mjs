// The email itself: subject, HTML and plain text, in Spanish (Colombia).
//
// Every value from the event is escaped before it reaches the HTML. The buyer
// typed their name and address, so to this code they are untrusted input.

const COLORS = {
  brand: '#3e2723',
  text: '#2b2118',
  muted: '#6d5d52',
  border: '#e7ded6',
  background: '#faf7f4',
  approved: '#2e7d32',
  refused: '#b3261e',
};

const escapeHtml = (value) =>
  String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

export const formatMoney = (cents, currency) =>
  new Intl.NumberFormat('es-CO', {
    style: 'currency',
    currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  })
    .format(cents / 100)
    // Intl separates the symbol with a no-break space; some mail clients show it as "Â".
    .replaceAll(' ', ' ');

const formatDate = (iso) =>
  new Intl.DateTimeFormat('es-CO', {
    dateStyle: 'long',
    timeZone: 'America/Bogota',
  }).format(new Date(iso));

/** The order's short reference: enough to recognise it, without the whole id. */
const shortReference = (transactionId) => transactionId.slice(0, 8).toUpperCase();

const addressLines = (delivery) =>
  [
    delivery.addressLine1,
    delivery.addressLine2,
    [delivery.city, delivery.region].join(', '),
    delivery.postalCode,
  ].filter((line) => line !== undefined && line !== '');

const copyFor = (event) =>
  event.status === 'APPROVED'
    ? {
        subject: `¡Tu pago fue aprobado! · Pedido ${shortReference(event.transactionId)}`,
        heading: '¡Tu pago fue aprobado!',
        intro: 'Gracias por tu compra. Ya estamos preparando tu pedido.',
        color: COLORS.approved,
        action: 'Ver mi pedido',
      }
    : {
        subject: `No pudimos procesar tu pago · Pedido ${shortReference(event.transactionId)}`,
        heading: 'No pudimos procesar tu pago',
        intro:
          'Tu pago no fue aprobado y no se realizó ningún cobro. Puedes intentarlo de nuevo con otra tarjeta.',
        color: COLORS.refused,
        action: 'Ver el estado del pedido',
      };

/** Builds the email for a payment event. `storefrontUrl` has no trailing slash. */
export const renderEmail = (event, storefrontUrl) => {
  const copy = copyFor(event);
  const { amounts, delivery } = event;
  const money = (cents) => formatMoney(cents, amounts.currency);
  const orderUrl = `${storefrontUrl}/orders/${encodeURIComponent(event.transactionId)}`;
  const reference = shortReference(event.transactionId);
  const firstName = event.customer.fullName.trim().split(/\s+/)[0];
  const estimated =
    event.status === 'APPROVED' && delivery.estimatedDeliveryAt !== undefined
      ? formatDate(delivery.estimatedDeliveryAt)
      : undefined;

  const totals = [
    ['Productos', amounts.productInCents],
    ['Tarifa base', amounts.baseFeeInCents],
    ['Envío', amounts.deliveryFeeInCents],
  ];

  const text = [
    `Hola, ${firstName}:`,
    '',
    copy.heading,
    copy.intro,
    '',
    `Pedido ${reference}`,
    ...event.lines.map(
      (line) => `- ${line.name} × ${line.units}: ${money(line.lineTotalInCents)}`,
    ),
    '',
    ...totals.map(([label, cents]) => `${label}: ${money(cents)}`),
    `Total: ${money(amounts.totalInCents)}`,
    '',
    'Entrega',
    event.customer.fullName,
    ...addressLines(delivery),
    ...(estimated === undefined ? [] : [`Entrega estimada: ${estimated}`]),
    '',
    `${copy.action}: ${orderUrl}`,
    '',
    'ADH Shop · Café de especialidad',
  ].join('\n');

  const row = (label, value, strong = false) => `
          <tr>
            <td style="padding:6px 0;color:${strong ? COLORS.text : COLORS.muted};${strong ? 'font-weight:700;' : ''}">${escapeHtml(label)}</td>
            <td style="padding:6px 0;text-align:right;color:${COLORS.text};${strong ? 'font-weight:700;' : ''}">${escapeHtml(value)}</td>
          </tr>`;

  const html = `<!doctype html>
<html lang="es-CO">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(copy.subject)}</title>
  </head>
  <body style="margin:0;padding:0;background:${COLORS.background};font-family:Arial,Helvetica,sans-serif;color:${COLORS.text};">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${COLORS.background};padding:24px 12px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border:1px solid ${COLORS.border};border-radius:12px;">
            <tr>
              <td style="padding:20px 24px;background:${COLORS.brand};border-radius:12px 12px 0 0;color:#ffffff;font-size:18px;font-weight:700;">ADH Shop</td>
            </tr>
            <tr>
              <td style="padding:24px;">
                <p style="margin:0 0 8px;">Hola, ${escapeHtml(firstName)}:</p>
                <h1 style="margin:0 0 8px;font-size:22px;color:${copy.color};">${escapeHtml(copy.heading)}</h1>
                <p style="margin:0 0 20px;color:${COLORS.muted};">${escapeHtml(copy.intro)}</p>

                <p style="margin:0 0 8px;font-weight:700;">Pedido ${escapeHtml(reference)}</p>
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid ${COLORS.border};">
                  ${event.lines
                    .map(
                      (line) => `
                  <tr>
                    <td style="padding:10px 0;border-bottom:1px solid ${COLORS.border};">
                      ${escapeHtml(line.name)}<br />
                      <span style="color:${COLORS.muted};font-size:13px;">${escapeHtml(`${line.units} × ${money(line.unitPriceInCents)}`)}</span>
                    </td>
                    <td style="padding:10px 0;border-bottom:1px solid ${COLORS.border};text-align:right;">${escapeHtml(money(line.lineTotalInCents))}</td>
                  </tr>`,
                    )
                    .join('')}
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:12px;">
                  ${totals.map(([label, cents]) => row(label, money(cents))).join('')}
                  ${row('Total', money(amounts.totalInCents), true)}
                </table>

                <p style="margin:20px 0 4px;font-weight:700;">Entrega</p>
                <p style="margin:0;color:${COLORS.muted};line-height:1.5;">
                  ${[event.customer.fullName, ...addressLines(delivery)].map(escapeHtml).join('<br />')}
                </p>
                ${
                  estimated === undefined
                    ? ''
                    : `<p style="margin:8px 0 0;">Entrega estimada: <strong>${escapeHtml(estimated)}</strong></p>`
                }

                <p style="margin:28px 0 0;">
                  <a href="${escapeHtml(orderUrl)}" style="display:inline-block;padding:12px 20px;background:${COLORS.brand};color:#ffffff;text-decoration:none;border-radius:8px;font-weight:700;">${escapeHtml(copy.action)}</a>
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:16px 24px;border-top:1px solid ${COLORS.border};color:${COLORS.muted};font-size:12px;">
                ADH Shop · Café de especialidad. Recibes este correo porque hiciste un pedido en nuestra tienda.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;

  return { subject: copy.subject, text, html };
};
