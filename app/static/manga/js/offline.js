// The offline page: the shell only, and a reload once the connection is back.
import { initShell } from "./ui.js";

initShell();
addEventListener("online", () => location.reload());
