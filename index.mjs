import {SSMClient, GetParameterCommand} from "@aws-sdk/client-ssm";
import {getSignedUrl} from "@aws-sdk/s3-request-presigner";
import {S3Client, GetObjectCommand} from "@aws-sdk/client-s3";

const cacheOperation = (fn, cacheTime) => {
	let lastRefreshed = undefined;
	let lastResult = undefined;
	let queue = Promise.resolve();
	return () => {
		const res = queue.then(async () => {
			const currentTime = new Date().getTime();
			if (lastResult === undefined || lastRefreshed + cacheTime < currentTime) {
				lastResult = await fn();
				lastRefreshed = currentTime;
			}
			return lastResult;
		});
		queue = res.catch(() => {});
		return res;
	};
};

const getSecretAccessKey = cacheOperation(() => new SSMClient().send(new GetParameterCommand({Name: process.env.SECRET_ACCESS_KEY_PARAMETER, WithDecryption: true})), 15 * 1000);

const roundTo = 5 * 60 * 1000; // 5 minutes

export const handler = async (event) => {
	const Key = "test.jpg";
	const Bucket = process.env.IMAGES_BUCKET;

	const baseSign = async () => {
		return getSignedUrl(new S3Client(), new GetObjectCommand({
			Bucket,
			Key,
		}));
	};

	const fixedTimeSign = async () => {
		return getSignedUrl(new S3Client(), new GetObjectCommand({
			Bucket,
			Key,
		}), {signingDate: new Date(Math.floor(new Date().getTime() / roundTo) * roundTo)});
	};

	const stableSign = async () => {
		const accessKeyId = process.env.ACCESS_KEY_ID;
		const secretAccessKey = (await getSecretAccessKey()).Parameter.Value;
		return getSignedUrl(new S3Client({
			credentials: {
				accessKeyId,
				secretAccessKey,
			},
		}), new GetObjectCommand({
			Bucket,
			Key,
		}), {signingDate: new Date(Math.floor(new Date().getTime() / roundTo) * roundTo)});
	};

	if (event.rawPath.match(/^\/?base\//) !== null) {
		return {
			statusCode: 200,
			body: await baseSign(),
		};
	}
	if (event.rawPath.match(/^\/?fixed_time\//) !== null) {
		return {
			statusCode: 200,
			body: await fixedTimeSign(),
		};
	}
	if (event.rawPath.match(/^\/?stable\//) !== null) {
		return {
			statusCode: 200,
			body: await stableSign(),
		};
	}

	return {
		statusCode: 200,
		headers: {
			"Content-Type": "text/html",
		},
		body: `
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
  </head>
  <body>
	<h2>Normal signing:</h2>
	${(await Promise.all([0,1,2,3,4].map(async (i) => `<iframe style="display: block; width: 100%;" src="/base/${i}"></iframe>`))).join("")}
	<h2>Fixed time signing:</h2>
	${(await Promise.all([0,1,2,3,4].map(async (i) => `<iframe style="display: block; width: 100%;" src="/fixed_time/${i}"></iframe>`))).join("")}
	<h2>Stable signing:</h2>
	${(await Promise.all([0,1,2,3,4].map(async (i) => `<iframe style="display: block; width: 100%;" src="/stable/${i}"></iframe>`))).join("")}
  </body>
</html>
			`,
	};
};


