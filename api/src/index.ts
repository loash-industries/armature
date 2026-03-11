import express from "express";

const app = express();

app.get("/", (req, res) => {
  res.send("Hello, world! This is my Node.js API.");
});

app.get("/health", (req, res) => {
  res.send("OK");
});

app.get("/metrics", (req, res) => {
  res.type("text/plain").send("# No metrics\n");
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
