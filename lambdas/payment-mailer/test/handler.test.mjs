import assert from 'node:assert/strict';
import { beforeEach, describe, it, mock } from 'node:test';

import { createHandler, loadGmailSend } from '../src/handler.mjs';
import { readCredentials } from '../src/mailer.mjs';
import { aRecord, anEvent } from './fixtures.mjs';

describe('handler', () => {
  let sent;
  let loads;
  let handler;

  beforeEach(() => {
    sent = [];
    loads = 0;
    // Keep the test output clean; the handler logs every outcome.
    mock.method(console, 'info', () => {});
    mock.method(console, 'error', () => {});
    handler = createHandler({
      loadSend: async () => {
        loads += 1;
        return async (message) => {
          sent.push(message);
        };
      },
      storefrontUrl: 'https://shop.example',
    });
  });

  it('emails the buyer and reports no failures', async () => {
    const result = await handler({ Records: [aRecord(anEvent())] });

    assert.deepEqual(result, { batchItemFailures: [] });
    assert.equal(sent.length, 1);
    assert.equal(sent[0].to, 'laura@example.com');
    assert.match(sent[0].subject, /aprobado/);
    assert.ok(sent[0].html.includes('<html'));
    assert.ok(sent[0].text.includes('Total'));
  });

  it('retries only the message that failed', async () => {
    const result = await handler({
      Records: [
        aRecord(anEvent(), 'good-1'),
        aRecord('{"broken"', 'bad'),
        aRecord(anEvent({ status: 'DECLINED' }), 'good-2'),
      ],
    });

    assert.deepEqual(result, { batchItemFailures: [{ itemIdentifier: 'bad' }] });
    assert.equal(sent.length, 2);
  });

  it('reuses the transport while sends succeed', async () => {
    await handler({ Records: [aRecord(anEvent(), 'a'), aRecord(anEvent(), 'b')] });

    assert.equal(loads, 1);
  });

  it('reads the credentials again after a failed send, so a rotated password is picked up', async () => {
    const passwords = [];
    handler = createHandler({
      loadSend: async () => {
        const password = passwords.length === 0 ? 'old' : 'new';
        passwords.push(password);
        return async () => {
          if (password === 'old') throw new Error('Invalid login');
        };
      },
      storefrontUrl: 'https://shop.example',
    });

    const result = await handler({
      Records: [aRecord(anEvent(), 'first'), aRecord(anEvent(), 'second')],
    });

    assert.deepEqual(passwords, ['old', 'new']);
    assert.deepEqual(result, { batchItemFailures: [{ itemIdentifier: 'first' }] });
  });

  it('reports the message when Gmail refuses it, so SQS retries it', async () => {
    handler = createHandler({
      loadSend: async () => async () => {
        throw new Error('Invalid login');
      },
      storefrontUrl: 'https://shop.example',
    });

    const result = await handler({ Records: [aRecord(anEvent(), 'm-1')] });

    assert.deepEqual(result, { batchItemFailures: [{ itemIdentifier: 'm-1' }] });
  });

  it('never logs the buyer’s email or name', async () => {
    await handler({ Records: [aRecord(anEvent())] });

    const logged = console.info.mock.calls.map((call) => call.arguments.join(' ')).join('\n');
    assert.ok(logged.includes('6f1c2b9e-8f4a-4d7e-9a51-1b2c3d4e5f60'));
    assert.ok(!logged.includes('laura@example.com'));
    assert.ok(!logged.includes('Laura'));
  });
});

describe('loadGmailSend', () => {
  it('sends as the Gmail account, under the configured display name', async () => {
    const mails = [];
    const send = await loadGmailSend({
      parameterPath: '/mailer',
      fromName: 'ADH Shop',
      read: async (path) => {
        assert.equal(path, '/mailer');
        return { user: 'store@gmail.com', password: 'app-password' };
      },
      transportFor: (credentials) => {
        assert.deepEqual(credentials, { user: 'store@gmail.com', password: 'app-password' });
        return { sendMail: async (mail) => mails.push(mail) };
      },
    });

    await send({ to: 'a@example.com', subject: 's', text: 't', html: 'h' });

    assert.deepEqual(mails[0], {
      from: { name: 'ADH Shop', address: 'store@gmail.com' },
      to: 'a@example.com',
      subject: 's',
      text: 't',
      html: 'h',
    });
  });
});

describe('readCredentials', () => {
  const ssmReturning = (parameters) => ({
    send: async (command) => {
      assert.equal(command.input.Path, '/mailer');
      assert.equal(command.input.WithDecryption, true);
      return { Parameters: parameters };
    },
  });

  it('reads both values from the path, decrypted', async () => {
    const credentials = await readCredentials(
      '/mailer',
      ssmReturning([
        { Name: '/mailer/MAIL_USER', Value: 'store@gmail.com' },
        { Name: '/mailer/MAIL_PASSWORD', Value: 'app-password' },
      ]),
    );

    assert.deepEqual(credentials, { user: 'store@gmail.com', password: 'app-password' });
  });

  it('fails clearly when one is missing', async () => {
    await assert.rejects(
      readCredentials('/mailer', ssmReturning([{ Name: '/mailer/MAIL_USER', Value: 'x' }])),
      /MAIL_USER and MAIL_PASSWORD must both exist under \/mailer/,
    );
  });
});
