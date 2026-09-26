// SQS → email. One record per invocation in practice (batch size 1), but the
// handler reports failures per record, so a larger batch would still retry
// only the messages that failed.
//
// Delivery is at least once. A crash after Gmail accepted the email but before
// the message was deleted would send it again; with one record per batch that
// window is a few milliseconds, and a repeated confirmation email was judged
// an acceptable cost against a deduplication store.

import { renderEmail } from './email.mjs';
import { parsePaymentEvent } from './event.mjs';
import { createTransport, readCredentials } from './mailer.mjs';

const log = (level, message, fields = {}) =>
  console[level](JSON.stringify({ level, message, ...fields }));

/**
 * Builds the handler. `loadSend` resolves, once per container, to a function
 * that sends one message. Injected so tests run without AWS or Gmail.
 */
export const createHandler = ({ loadSend, storefrontUrl }) => {
  let send;

  return async (sqsEvent) => {
    const batchItemFailures = [];

    for (const record of sqsEvent.Records) {
      try {
        const event = parsePaymentEvent(record.body);
        send ??= await loadSend();

        const email = renderEmail(event, storefrontUrl);
        await send({
          to: event.customer.email,
          subject: email.subject,
          text: email.text,
          html: email.html,
        });

        // No address, no name: the transaction id is enough to find the order.
        log('info', 'Payment email sent', {
          transactionId: event.transactionId,
          status: event.status,
        });
      } catch (error) {
        // Start over on the next message: after a password rotation, the
        // cached transport would keep failing with the old one.
        send = undefined;
        log('error', 'Payment email failed', {
          messageId: record.messageId,
          error: error instanceof Error ? error.message : String(error),
        });
        batchItemFailures.push({ itemIdentifier: record.messageId });
      }
    }

    return { batchItemFailures };
  };
};

/** Gmail, with the credentials from Parameter Store. */
export const loadGmailSend = async ({
  parameterPath,
  fromName,
  read = readCredentials,
  transportFor = createTransport,
}) => {
  const credentials = await read(parameterPath);
  const transport = transportFor(credentials);
  // Gmail sends as the authenticated account whatever `from` says, so the
  // display name is the only part worth choosing.
  const from = { name: fromName, address: credentials.user };
  return (message) => transport.sendMail({ from, ...message });
};

export const handler = createHandler({
  loadSend: () =>
    loadGmailSend({
      parameterPath: process.env.MAIL_PARAMETER_PATH ?? '/adh-shop-mailer',
      fromName: process.env.MAIL_FROM_NAME ?? 'ADH Shop',
    }),
  storefrontUrl: process.env.STOREFRONT_URL ?? 'https://adh-shop.alfredo-dominguez.dev',
});
