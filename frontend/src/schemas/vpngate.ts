import { z } from 'zod';

// Mirrors internal/web/service/vpngate.go VPNGateServer (json tags).
export const VPNGateServerSchema = z
  .object({
    hostName: z.string(),
    ip: z.string(),
    countryLong: z.string(),
    countryShort: z.string(),
    countryShortLower: z.string(),
    numSessions: z.number(),
    isp: z.string(),
    asn: z.string(),
    ipType: z.string(),
    localPing: z.number(),
    proto: z.string(),
    port: z.string(),
    openVPNConfig: z.string(),
  })
  .loose();

export const VPNGateServerListSchema = z.array(VPNGateServerSchema);

// Mirrors internal/web/service/openvpn.go OpenVPNStatus.
export const OpenVPNStatusSchema = z
  .object({
    phase: z.string(),
    progress: z.number(),
    message: z.string(),
    error: z.string().optional(),
    tunIP: z.string().optional(),
    tunDev: z.string().optional(),
    server: VPNGateServerSchema.nullish(),
    log: z.array(z.string()).optional(),
  })
  .loose();

// GET /settings response. Note: selectedCountries arrives as a JSON string from
// the backend (persisted verbatim); the page parses it into an array.
export const VPNGateSettingsSchema = z
  .object({
    ruleMode: z.string(),
    selectedCountries: z.string(),
    fallbackEnable: z.boolean(),
  })
  .loose();

export type VPNGateServer = z.infer<typeof VPNGateServerSchema>;
export type OpenVPNStatus = z.infer<typeof OpenVPNStatusSchema>;
export type VPNGateSettings = z.infer<typeof VPNGateSettingsSchema>;

// Shape sent to POST /settings / POST /start (selectedCountries is a real array).
export interface VPNGateSettingsInput {
  ruleMode: string;
  selectedCountries: string[];
  fallbackEnable: boolean;
}
