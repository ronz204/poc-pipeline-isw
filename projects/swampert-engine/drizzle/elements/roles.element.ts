import { pgRole } from "drizzle-orm/pg-core";

export const runner = pgRole("runner").existing();
export const backuper = pgRole("backuper").existing();
