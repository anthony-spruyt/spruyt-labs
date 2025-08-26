data "aws_iam_policy_document" "tfc_oidc_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type = "Federated"
      identifiers = [
        "arn:aws:iam::${var.aws_account_id}:oidc-provider/app.terraform.io"
      ]
    }

    # Restrict to your org's workspaces and run phases
    condition {
      test     = "StringEquals"
      variable = "app.terraform.io:aud"
      values   = ["aws.workload.identity"]
    }

    condition {
      test     = "StringLike"
      variable = "app.terraform.io:sub"
      values = [
        "organization:${var.tfc_org_name}:project:*:workspace:*:run_phase:*"
      ]
    }
  }
}

resource "aws_iam_role" "tfc_oidc" {
  name               = "tfc-oidc-terraform"
  assume_role_policy = data.aws_iam_policy_document.tfc_oidc_trust.json
}

# least-privilege inline policy — adjust to Ceph stack's needs
data "aws_iam_policy_document" "tfc_oidc_policy" {
  statement {
    actions = [
      "s3:*",
      "kms:*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "tfc_oidc_inline" {
  name   = "tfc-oidc-inline"
  role   = aws_iam_role.tfc_oidc.id
  policy = data.aws_iam_policy_document.tfc_oidc_policy.json
}

output "tfc_oidc_role_arn" {
  value = aws_iam_role.tfc_oidc.arn
}
