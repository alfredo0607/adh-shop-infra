import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { formatMoney, renderEmail } from '../src/email.mjs';
import { anEvent } from './fixtures.mjs';

const STORE = 'https://shop.example';

describe('renderEmail', () => {
  it('confirms an approved payment with the order, the amounts and the delivery', () => {
    const { subject, text, html } = renderEmail(anEvent(), STORE);

    assert.equal(subject, '¡Tu pago fue aprobado! · Pedido 6F1C2B9E');
    for (const part of [
      'Hola, Laura:',
      '- Cafetera espresso Artigiano × 1: $ 89.990',
      '- Filtros de papel × 100 × 2: $ 5.000',
      'Productos: $ 94.990',
      'Tarifa base: $ 500',
      'Envío: $ 1.200',
      'Total: $ 96.690',
      'Laura Gómez',
      'Calle 93 # 11-26',
      'Apto 502',
      'Bogotá, Bogotá D.C.',
      'Entrega estimada: 29 de septiembre de 2026',
      `Ver mi pedido: ${STORE}/orders/6f1c2b9e-8f4a-4d7e-9a51-1b2c3d4e5f60`,
    ]) {
      assert.ok(text.includes(part), `text is missing "${part}"`);
    }
    assert.ok(html.includes('¡Tu pago fue aprobado!'));
    assert.ok(html.includes('$ 96.690'));
    assert.ok(html.includes(`href="${STORE}/orders/6f1c2b9e-8f4a-4d7e-9a51-1b2c3d4e5f60"`));
  });

  it('says a refused payment charged nothing, and promises no delivery date', () => {
    for (const status of ['DECLINED', 'VOIDED', 'ERROR']) {
      const { subject, text } = renderEmail(anEvent({ status }), STORE);

      assert.equal(subject, 'No pudimos procesar tu pago · Pedido 6F1C2B9E');
      assert.ok(text.includes('no se realizó ningún cobro'));
      assert.ok(!text.includes('Entrega estimada'));
      assert.ok(text.includes('Ver el estado del pedido'));
    }
  });

  it('escapes what the buyer typed', () => {
    const event = anEvent({
      customer: { fullName: '<script>alert(1)</script> Ana', email: 'ana@example.com' },
      delivery: { ...anEvent().delivery, addressLine1: 'Calle "5" & <b>7</b>' },
    });

    const { html } = renderEmail(event, STORE);

    assert.ok(!html.includes('<script>'));
    assert.ok(html.includes('&lt;script&gt;alert(1)&lt;/script&gt; Ana'));
    assert.ok(html.includes('Calle &quot;5&quot; &amp; &lt;b&gt;7&lt;/b&gt;'));
  });

  it('leaves out address lines the buyer did not give', () => {
    const delivery = { addressLine1: 'Calle 1', city: 'Cali', region: 'Valle', country: 'CO' };

    const { text } = renderEmail(anEvent({ delivery }), STORE);

    assert.ok(text.includes('Calle 1\nCali, Valle\n'));
    assert.ok(!text.includes('undefined'));
  });
});

describe('formatMoney', () => {
  it('formats pesos without decimals and with a plain space', () => {
    assert.equal(formatMoney(9_169_000, 'COP'), '$ 91.690');
  });
});
