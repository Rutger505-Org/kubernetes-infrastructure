// @ts-check

/**
 * @typedef {import('@actions/github').context} Context
 * @typedef {ReturnType<import('@actions/github').getOctokit>} GitHub
 * @typedef {typeof core} Core
 */

/**
 * Lists the numbers of every open pull request in the current repository.
 *
 * Used by the scheduled cleanup job to decide which `pr-<number>` environments
 * still belong to an open pull request. Any environment whose pull request is
 * no longer open is considered abandoned and gets destroyed.
 *
 * @param {Object} params
 * @param {GitHub} params.github
 * @param {Context} params.context
 * @param {Core} params.core
 * @returns {Promise<number[]>}
 */
export default async function listOpenPullRequests({ github, context, core }) {
  try {
    const { owner, repo } = context.repo;

    const pullRequests = await github.paginate(github.rest.pulls.list, {
      owner,
      repo,
      state: "open",
      per_page: 100,
    });

    const numbers = pullRequests.map((pullRequest) => pullRequest.number);

    core.info(`Open pull requests: ${numbers.join(", ") || "(none)"}`);
    core.setOutput("numbers", numbers.join(" "));

    return numbers;
  } catch (error) {
    if (error instanceof Error) {
      core.setFailed(error.message);
    }
    throw error;
  }
}
