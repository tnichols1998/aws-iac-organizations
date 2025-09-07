# GitHub Actions Terraform Outputs
# Generated automatically by bootstrap Terraform configuration

AWS_ROLE_ARN: "${github_actions_role_arn}"
AWS_REGION: "${region}"
ORGANIZATION_NAME: "${organization_name}"

# Use these in your GitHub Actions workflows:
# - name: Configure AWS credentials
#   uses: aws-actions/configure-aws-credentials@v4
#   with:
#     role-to-assume: ${github_actions_role_arn}
#     role-session-name: github-actions-session
#     aws-region: ${region}
