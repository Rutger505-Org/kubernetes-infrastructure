// @ts-check

function pickEntriesWithKeyPrefix(prefix, object) {
  const picked = Object.entries(object)
    .filter(([key]) => key.startsWith(prefix))
    .map(([key, value]) => {
      const newKey = key.replace(prefix, "");
      return [newKey, value];
    });

  return Object.fromEntries(picked);
}

export default async function generateDeploymentEnvironment(
  core,
  { filterPrefix, unfilteredVars, vars, unfilteredSecrets, secrets },
) {
  try {
    const filteredVars = pickEntriesWithKeyPrefix(filterPrefix, unfilteredVars);
    const filteredSecrets = pickEntriesWithKeyPrefix(
      filterPrefix,
      unfilteredSecrets,
    );

    const config = {
      vars: { ...filteredVars, ...vars },
      secrets: { ...filteredSecrets, ...secrets },
    };

    Object.entries(config).forEach(([key, value]) => {
      core.setOutput(key, value);
      core.info(`${key}: ${JSON.stringify(value)}`);
    });

    return config;
  } catch (error) {
    if (error instanceof Error) {
      core.setFailed(error.message);
    }
    throw error;
  }
}
