resource "aws_iam_user" "signer" {
  name = "signer-${random_id.id.hex}"
}

resource "aws_iam_user_policy" "signer" {
  user = aws_iam_user.signer.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
        ]
        Effect   = "Allow"
				Resource = "${aws_s3_bucket.images.arn}/*"
      },
    ]
  })
}

module "access_key" {
	source  = "sashee/ssm-generated-value/aws"
	parameter_name = "/accesskey-${random_id.id.hex}"
	code = <<EOF
import {IAMClient, CreateAccessKeyCommand, ListAccessKeysCommand, DeleteAccessKeyCommand} from "@aws-sdk/client-iam";

const client = new IAMClient();
const UserName = "${aws_iam_user.signer.name}";

export const generate = async () => {
	const result = await client.send(new CreateAccessKeyCommand({
		UserName,
	}));
	return {
		value: result.AccessKey.SecretAccessKey,
		outputs: {
			AccessKeyId: result.AccessKey.AccessKeyId,
		}
	};
}

export const cleanup = async () => {
	const list = await client.send(new ListAccessKeysCommand({
		UserName,
	}));
	await Promise.all(list.AccessKeyMetadata.map(async ({AccessKeyId}) => {
		await client.send(new DeleteAccessKeyCommand({
			UserName,
			AccessKeyId,
		}));
	}));
}
EOF
	extra_statements = [
		{
			"Action": [
				"iam:CreateAccessKey",
				"iam:ListAccessKeys",
				"iam:DeleteAccessKey"
			],
			"Effect": "Allow",
			"Resource": aws_iam_user.signer.arn
		}
	]
}

