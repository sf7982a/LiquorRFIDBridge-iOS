declare module "@vercel/analytics/react" {
  import type { FC } from "react";
  export const Analytics: FC<Record<string, unknown>>;
}

declare module "@vercel/speed-insights/next" {
  import type { FC } from "react";
  export const SpeedInsights: FC<Record<string, unknown>>;
}


