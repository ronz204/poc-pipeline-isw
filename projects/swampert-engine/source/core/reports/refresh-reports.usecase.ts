import type { ReportsPort } from "@core/reports/reports.port";

export class RefreshReportsUseCase {
  constructor(private readonly port: ReportsPort) {};

  public execute(period: Date): Promise<void> {
    return this.port.refresh(period);
  };
};
