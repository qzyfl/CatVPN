import { useMutation, useQueryClient } from '@tanstack/react-query';

import { HttpUtil } from '@/utils';
import { keys } from '@/api/queryKeys';
import type { VPNGateServer, VPNGateSettingsInput } from '@/schemas/vpngate';

const JSON_HEADERS = { headers: { 'Content-Type': 'application/json' } };

export function useVPNGateMutations() {
  const queryClient = useQueryClient();
  const invalidateStatus = () => queryClient.invalidateQueries({ queryKey: keys.vpngate.status() });
  const invalidateServers = () =>
    queryClient.invalidateQueries({ queryKey: keys.vpngate.servers(false, false) });

  const startMut = useMutation({
    mutationFn: (payload: {
      server: VPNGateServer;
      ruleMode: string;
      selectedCountries: string[];
      fallbackEnable: boolean;
    }) => HttpUtil.post('/panel/api/vpngate/start', payload, { ...JSON_HEADERS, silent: true }),
    onSuccess: (msg) => {
      if (msg?.success) {
        invalidateStatus();
        invalidateServers();
      }
    },
  });

  const stopMut = useMutation({
    mutationFn: () => HttpUtil.post('/panel/api/vpngate/stop', undefined, { silent: true }),
    onSuccess: (msg) => {
      if (msg?.success) invalidateStatus();
    },
  });

  const cancelMut = useMutation({
    mutationFn: () => HttpUtil.post('/panel/api/vpngate/cancel', undefined, { silent: true }),
    onSuccess: (msg) => {
      if (msg?.success) invalidateStatus();
    },
  });

  const repairMut = useMutation({
    mutationFn: () => HttpUtil.post('/panel/api/vpngate/repair', undefined, { silent: true }),
    onSuccess: (msg) => {
      if (msg?.success) invalidateStatus();
    },
  });

  const refreshMut = useMutation({
    mutationFn: () => HttpUtil.post('/panel/api/vpngate/refresh', undefined, { silent: true }),
    onSuccess: (msg) => {
      if (msg?.success) invalidateServers();
    },
  });

  const updateSettingsMut = useMutation({
    mutationFn: (payload: VPNGateSettingsInput) =>
      HttpUtil.post('/panel/api/vpngate/settings', payload, { ...JSON_HEADERS, silent: true }),
    onSuccess: (msg) => {
      if (msg?.success) {
        queryClient.invalidateQueries({ queryKey: keys.vpngate.settings() });
        invalidateStatus();
      }
    },
  });

  return {
    start: (payload: {
      server: VPNGateServer;
      ruleMode: string;
      selectedCountries: string[];
      fallbackEnable: boolean;
    }) => startMut.mutateAsync(payload),
    stop: () => stopMut.mutateAsync(),
    cancel: () => cancelMut.mutateAsync(),
    repair: () => repairMut.mutateAsync(),
    refresh: () => refreshMut.mutateAsync(),
    updateSettings: (payload: VPNGateSettingsInput) => updateSettingsMut.mutateAsync(payload),
  };
}
