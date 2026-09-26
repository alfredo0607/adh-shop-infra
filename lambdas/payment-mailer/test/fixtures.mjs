export const anEvent = (overrides = {}) => ({
  type: 'payment.settled',
  version: 1,
  transactionId: '6f1c2b9e-8f4a-4d7e-9a51-1b2c3d4e5f60',
  status: 'APPROVED',
  occurredAt: '2026-09-26T21:00:00.000Z',
  customer: { fullName: 'Laura Gómez', email: 'laura@example.com' },
  lines: [
    {
      name: 'Cafetera espresso Artigiano',
      units: 1,
      unitPriceInCents: 8_999_000,
      lineTotalInCents: 8_999_000,
    },
    {
      name: 'Filtros de papel × 100',
      units: 2,
      unitPriceInCents: 250_000,
      lineTotalInCents: 500_000,
    },
  ],
  amounts: {
    productInCents: 9_499_000,
    baseFeeInCents: 50_000,
    deliveryFeeInCents: 120_000,
    totalInCents: 9_669_000,
    currency: 'COP',
  },
  delivery: {
    addressLine1: 'Calle 93 # 11-26',
    addressLine2: 'Apto 502',
    city: 'Bogotá',
    region: 'Bogotá D.C.',
    country: 'CO',
    estimatedDeliveryAt: '2026-09-29T21:00:00.000Z',
  },
  ...overrides,
});

export const aRecord = (body, messageId = 'msg-1') => ({
  messageId,
  body: typeof body === 'string' ? body : JSON.stringify(body),
});
