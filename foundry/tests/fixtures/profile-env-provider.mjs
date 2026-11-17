process.stdout.write(
  [
    process.env.QAF_MODEL,
    process.env.QAF_REASONING_EFFORT,
    process.env.PROVIDER_TOKEN,
  ].join("|"),
);

