import { useQuery } from '@tanstack/react-query';
import { useMemo } from 'react';

import { HttpUtil } from '@/utils';
import { parseMsg } from '@/utils/zodValidate';
import {
  VPNGateServerListSchema,
  OpenVPNStatusSchema,
  VPNGateSettingsSchema,
  type VPNGateServer,
  type OpenVPNStatus,
  type VPNGateSettings,
} from '@/schemas/vpngate';
import { keys } from '@/api/queryKeys';

const DEFAULT_SETTINGS: VPNGateSettings = {
  ruleMode: 'default',
  selectedCountries: '[]',
  fallbackEnable: true,
};

// Phases that mean a connection attempt is still in flight; we poll faster then.
const ACTIVE_PHASES = new Set(['connecting', 'recovering', 'starting', 'preparing', 'testing']);

export function useVPNGateServersQuery(refresh = false, includeUnavailable = false) {
  const query = useQuery({
    queryKey: keys.vpngate.servers(refresh, includeUnavailable),
    queryFn: async () => {
      const msg = await HttpUtil.get(
        '/panel/api/vpngate/servers',
        { refresh, includeUnavailable },
        { silent: true },
      );
      if (!msg?.success) throw new Error(msg?.msg || 'Failed to fetch VPNGate servers');
      const validated = parseMsg(msg, VPNGateServerListSchema, 'vpngate/servers');
      return Array.isArray(validated.obj) ? validated.obj : [];
    },
  });

  const servers = useMemo<VPNGateServer[]>(() => query.data ?? [], [query.data]);
  return {
    servers,
    loading: query.isFetching,
    fetched: query.data !== undefined || query.isError,
    fetchError: query.error ? (query.error as Error).message : '',
    refetch: query.refetch,
  };
}

export function useVPNGateStatusQuery() {
  const query = useQuery({
    queryKey: keys.vpngate.status(),
    queryFn: async () => {
      const msg = await HttpUtil.get('/panel/api/vpngate/status', undefined, { silent: true });
      if (!msg?.success) throw new Error(msg?.msg || 'Failed to fetch VPNGate status');
      const validated = parseMsg(msg, OpenVPNStatusSchema, 'vpngate/status');
      return validated.obj ?? null;
    },
    // Poll aggressively only while a tunnel is being established/repaired.
    refetchInterval: (ctx) => {
      const phase = (ctx.state.data as OpenVPNStatus | null | undefined)?.phase ?? 'idle';
      return ACTIVE_PHASES.has(phase) ? 1000 : 4000;
    },
  });

  const status = useMemo<OpenVPNStatus | null>(() => query.data ?? null, [query.data]);
  return {
    status,
    loading: query.isFetching,
    refetch: query.refetch,
  };
}

export function useVPNGateSettingsQuery() {
  const query = useQuery({
    queryKey: keys.vpngate.settings(),
    queryFn: async () => {
      const msg = await HttpUtil.get('/panel/api/vpngate/settings', undefined, { silent: true });
      if (!msg?.success) throw new Error(msg?.msg || 'Failed to fetch VPNGate settings');
      const validated = parseMsg(msg, VPNGateSettingsSchema, 'vpngate/settings');
      return (validated.obj ?? DEFAULT_SETTINGS) as VPNGateSettings;
    },
    staleTime: 30_000,
  });

  const settings = useMemo<VPNGateSettings>(() => query.data ?? DEFAULT_SETTINGS, [query.data]);
  return {
    settings,
    loading: query.isFetching,
    refetch: query.refetch,
  };
}
