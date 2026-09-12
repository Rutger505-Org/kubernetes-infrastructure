// @ts-check

/**
 * @typedef {Object} ConfigValues
 * @property {string} APPLICATION_NAME
 * @property {string} DOCKERHUB_USERNAME
 */

/**
 * @typedef {import('@actions/github').Context} Context
 * @typedef {typeof core} Core
 */

/**
 * @returns {{ applicationName: string, dockerhubUsername: string }}
 */
function validateApplicationConfig() {
  /** @type {Array<keyof ConfigValues>} */
  const requiredEnvVars = ["APPLICATION_NAME", "DOCKERHUB_USERNAME"];

  /** @type {ConfigValues} */
  const envVars = /** @type {any} */ (process.env);

  const missingEnvVars = requiredEnvVars.filter(
    (envVar) => !envVars[envVar]?.length,
  );

  if (missingEnvVars.length) {
    throw new Error(
      `Missing required environment variables: ${missingEnvVars.join(", ")}`,
    );
  }

  return {
    applicationName: envVars.APPLICATION_NAME,
    dockerhubUsername: envVars.DOCKERHUB_USERNAME,
  };
}

/**
 * @param {Object} params
 * @param {Context} params.context
 * @param {Core} params.core
 */
export default async function generateConfig({ context, core }) {
  try {
    const { applicationName, dockerhubUsername } = validateApplicationConfig();

    // On a pull_request "closed" event GitHub sets context.ref to the base
    // branch (refs/heads/main), not a PR ref, so isMain must also require
    // the push event or a merged PR gets misclassified as production and
    // its preview namespace never gets torn down.
    const isMain =
      context.eventName === "push" && context.ref === "refs/heads/main";

    const config = {
      application_name: applicationName,
      environment: isMain
        ? "production"
        : `pr-${context.payload.pull_request.number}`,
      is_production: isMain ? "true" : "false",
      image: `${dockerhubUsername}/${applicationName}:${context.sha}`,
      hostname: isMain
        ? process.env.BASE_DOMAIN
        : `${context.sha}.${process.env.BASE_DOMAIN}`,
      certificate_issuer: isMain
        ? "letsencrypt-production"
        : "letsencrypt-staging",
    };

    Object.entries(config).forEach(([key, value]) => {
      core.setOutput(key, value);
      core.info(`${key}: ${value}`);
    });

    const summary = `
# Deployment Configuration 🚀
| Parameter | Value |
| - | - |
${Object.entries(config)
  .map(([key, value]) => {
    return `| ${key} | ${value} |`;
  })
  .join("\n")}
    `;
    await core.summary.addRaw(summary).write();

    return config;
  } catch (error) {
    if (error instanceof Error) {
      core.setFailed(error.message);
    }
    throw error;
  }
}
