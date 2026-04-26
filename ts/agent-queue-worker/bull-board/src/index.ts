import express from "express";
import { createBullBoard } from "@bull-board/api";
import { BullMQAdapter } from "@bull-board/api/bullMQAdapter";
import { ExpressAdapter } from "@bull-board/express";
import { Queue } from "bullmq";

const port = parseInt(process.env.BULL_BOARD_PORT ?? "3001", 10);
const readOnly = process.env.READ_ONLY === "true";

const connection = {
  host: process.env.VALKEY_HOST!,
  port: parseInt(process.env.VALKEY_PORT ?? "6379", 10),
  password: process.env.VALKEY_PASSWORD!,
};

const prefix = process.env.QUEUE_PREFIX ?? "agent:queue";
const queue = new Queue("agent", { connection, prefix });

const serverAdapter = new ExpressAdapter();
serverAdapter.setBasePath("/");

createBullBoard({
  queues: [new BullMQAdapter(queue, { readOnlyMode: readOnly })],
  serverAdapter,
});

const app = express();
app.use("/", serverAdapter.getRouter());

app.listen(port, () => {
  console.log(`Bull Board running on port ${port} (read-only: ${readOnly})`);
});
