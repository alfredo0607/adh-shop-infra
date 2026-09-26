// Sends through Gmail's SMTP with an app password. The credentials live in
// Parameter Store, outside the API's parameter path, and are read once per
// container: a cold start pays for the call, warm invocations do not.

import { GetParametersByPathCommand, SSMClient } from '@aws-sdk/client-ssm';
import nodemailer from 'nodemailer';

/** Reads MAIL_USER and MAIL_PASSWORD under `path`, decrypted. */
export const readCredentials = async (path, ssm = new SSMClient({})) => {
  const { Parameters = [] } = await ssm.send(
    new GetParametersByPathCommand({ Path: path, WithDecryption: true }),
  );
  const byName = Object.fromEntries(
    Parameters.map((parameter) => [parameter.Name.split('/').pop(), parameter.Value]),
  );

  const user = byName.MAIL_USER;
  const password = byName.MAIL_PASSWORD;
  if (!user || !password) {
    throw new Error(`MAIL_USER and MAIL_PASSWORD must both exist under ${path}`);
  }
  return { user, password };
};

export const createTransport = ({ user, password }) =>
  nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user,
      // An app password, not the account's own: it can be revoked alone, and
      // it only grants mail.
      pass: password,
    },
  });
