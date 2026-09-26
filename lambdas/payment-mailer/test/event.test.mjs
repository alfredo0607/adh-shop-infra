import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { parsePaymentEvent } from '../src/event.mjs';
import { anEvent } from './fixtures.mjs';

describe('parsePaymentEvent', () => {
  it('accepts every settled status', () => {
    for (const status of ['APPROVED', 'DECLINED', 'VOIDED', 'ERROR']) {
      assert.equal(parsePaymentEvent(JSON.stringify(anEvent({ status }))).status, status);
    }
  });

  it('accepts a delivery without the optional fields', () => {
    const delivery = { addressLine1: 'Calle 1', city: 'Cali', region: 'Valle', country: 'CO' };

    assert.deepEqual(parsePaymentEvent(JSON.stringify(anEvent({ delivery }))).delivery, delivery);
  });

  it('refuses a body that is not JSON', () => {
    assert.throws(() => parsePaymentEvent('not json'), /not JSON/);
  });

  it('refuses a status that is not final', () => {
    assert.throws(
      () => parsePaymentEvent(JSON.stringify(anEvent({ status: 'PENDING' }))),
      /status/,
    );
  });

  it('refuses another version of the event', () => {
    assert.throws(() => parsePaymentEvent(JSON.stringify(anEvent({ version: 2 }))), /version/);
  });

  it('names every bad field at once', () => {
    const event = anEvent({
      customer: { fullName: '', email: 'nobody' },
      lines: [{ name: 'x', units: 0, unitPriceInCents: -1, lineTotalInCents: 1.5 }],
      amounts: { currency: 'COP' },
      delivery: { addressLine1: 'Calle 1', city: 'Cali', region: 'Valle', country: 'CO', postalCode: 110 },
    });

    assert.throws(
      () => parsePaymentEvent(JSON.stringify(event)),
      (error) =>
        [
          'customer.fullName',
          'customer.email',
          'lines[0].units',
          'lines[0].unitPriceInCents',
          'lines[0].lineTotalInCents',
          'amounts.totalInCents',
          'delivery.postalCode',
        ].every((field) => error.message.includes(field)),
    );
  });

  it('refuses an order without lines', () => {
    assert.throws(() => parsePaymentEvent(JSON.stringify(anEvent({ lines: [] }))), /lines/);
  });

  it('refuses a message with no fields at all', () => {
    assert.throws(() => parsePaymentEvent('null'), /type, version, transactionId/);
  });
});
