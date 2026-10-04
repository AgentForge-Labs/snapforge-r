# R-universe distribution

The official R source package is maintained in this monorepo under
\`packages/sdk-r\` and mirrored to the public
\`AgentForge-Labs/snapforge-r\` repository for registry consumption.

The AgentForge Labs universe registry is
\`AgentForge-Labs/agentforge-labs.r-universe.dev\`. Its \`packages.json\`
must contain:

\`\`\`json
[
  {
    "package": "snapforge",
    "url": "https://github.com/AgentForge-Labs/snapforge-r"
  }
]
\`\`\`

## Activation prerequisite

R-universe requires its GitHub App to be installed on the same GitHub
organization as the universe registry. Repository creation and package
publication are automated here, but GitHub App installation requires an
organization-owner installation/authorization action and cannot be completed
through the repository REST API.

After the R-universe GitHub App is installed for \`AgentForge-Labs\`, the
registry will track the public \`snapforge-r\` default branch and publish builds
at \`https://agentforge-labs.r-universe.dev\`.

## CRAN submission prerequisite

Before a CRAN submission, replace the intentionally non-personal placeholder
maintainer address in \`DESCRIPTION\` with a monitored AgentForge Labs address.
No private maintainer email is committed or guessed by this repository.

The package itself passes R CMD check; this contact-address change does not
require an API or package-code change.
