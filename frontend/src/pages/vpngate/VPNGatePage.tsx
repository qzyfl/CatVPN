import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Button,
  Card,
  Col,
  Descriptions,
  Divider,
  Progress,
  Radio,
  Row,
  Select,
  Space,
  Switch,
  Table,
  Tag,
  Typography,
  message,
} from 'antd';
import type { ColumnsType } from 'antd/es/table';
import {
  ApiOutlined,
  DisconnectOutlined,
  ReloadOutlined,
  StopOutlined,
  ToolOutlined,
} from '@ant-design/icons';

import { useVPNGateServersQuery, useVPNGateStatusQuery, useVPNGateSettingsQuery } from '@/api/queries/useVPNGateQuery';
import { useVPNGateMutations } from '@/api/queries/useVPNGateMutations';
import type { VPNGateServer } from '@/schemas/vpngate';

const { Title, Paragraph } = Typography;

const ACTIVE_PHASES = new Set(['installing', 'connecting', 'testing', 'recovering', 'starting', 'preparing']);

function parseCountries(raw: string | undefined): string[] {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v.map((x) => String(x)) : [];
  } catch {
    return [];
  }
}

export default function VPNGatePage() {
  const { t } = useTranslation();
  const [messageApi, messageContextHolder] = message.useMessage();

  const { servers, loading: serversLoading, refetch: refetchServers } = useVPNGateServersQuery(false, false);
  const { status } = useVPNGateStatusQuery();
  const { settings } = useVPNGateSettingsQuery();
  const {
    start,
    stop,
    cancel,
    repair,
    refresh,
    updateSettings,
  } = useVPNGateMutations();

  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [ruleMode, setRuleMode] = useState<string>('default');
  const [selectedCountries, setSelectedCountries] = useState<string[]>([]);
  const [fallbackEnable, setFallbackEnable] = useState<boolean>(true);
  const [savingSettings, setSavingSettings] = useState(false);
  const [busy, setBusy] = useState(false);

  // Sync the settings form once the settings query resolves (don't clobber edits).
  const settingsLoaded = useMemo(() => Boolean(settings?.ruleMode), [settings]);
  const appliedRuleMode = settings?.ruleMode ?? 'default';
  const appliedCountries = parseCountries(settings?.selectedCountries);
  const appliedFallback = settings?.fallbackEnable ?? true;

  const didInitSettings = useRef(false);
  useEffect(() => {
    if (didInitSettings.current || !settings?.ruleMode) return;
    didInitSettings.current = true;
    setRuleMode(settings.ruleMode);
    setSelectedCountries(parseCountries(settings.selectedCountries));
    setFallbackEnable(settings.fallbackEnable ?? true);
  }, [settings]);

  const isActive = useMemo(() => {
    const phase = status?.phase ?? 'idle';
    return ACTIVE_PHASES.has(phase) || Boolean(status?.tunIP);
  }, [status]);
  const isConnecting = useMemo(() => ACTIVE_PHASES.has(status?.phase ?? 'idle'), [status]);

  const countryOptions = useMemo(() => {
    const seen = new Set<string>();
    const opts: { label: string; value: string }[] = [];
    for (const s of servers) {
      if (s.countryShort && !seen.has(s.countryShort)) {
        seen.add(s.countryShort);
        opts.push({ label: `${s.countryLong} (${s.countryShort})`, value: s.countryShort });
      }
    }
    return opts;
  }, [servers]);

  const selectedServer = useMemo(
    () => servers.find((s) => `${s.ip}:${s.port}` === selectedKey) ?? null,
    [servers, selectedKey],
  );

  const onConnect = useCallback(async () => {
    if (!selectedServer) {
      messageApi.warning(t('pages.vpngate.selectFirst'));
      return;
    }
    setBusy(true);
    try {
      const msg = await start({
        server: selectedServer,
        ruleMode: appliedRuleMode,
        selectedCountries: appliedCountries,
        fallbackEnable: appliedFallback,
      });
      if (msg?.success) {
        messageApi.success(t('pages.vpngate.toasts.connectStart', { country: selectedServer.countryLong }));
      } else {
        messageApi.error(msg?.msg || t('pages.vpngate.toasts.connectFail'));
      }
    } finally {
      setBusy(false);
    }
  }, [selectedServer, start, appliedRuleMode, appliedCountries, appliedFallback, messageApi, t]);

  const onDisconnect = useCallback(async () => {
    setBusy(true);
    try {
      const msg = await stop();
      if (msg?.success) messageApi.success(t('pages.vpngate.toasts.disconnected'));
      else messageApi.error(msg?.msg || t('pages.vpngate.toasts.disconnectFail'));
    } finally {
      setBusy(false);
    }
  }, [stop, messageApi, t]);

  const onCancel = useCallback(async () => {
    setBusy(true);
    try {
      const msg = await cancel();
      if (msg?.success) messageApi.info(t('pages.vpngate.toasts.cancelled'));
      else messageApi.error(msg?.msg || t('pages.vpngate.toasts.cancelFail'));
    } finally {
      setBusy(false);
    }
  }, [cancel, messageApi, t]);

  const onRepair = useCallback(async () => {
    setBusy(true);
    try {
      const msg = await repair();
      if (msg?.success) messageApi.success(t('pages.vpngate.toasts.repairDone'));
      else messageApi.error(msg?.msg || t('pages.vpngate.toasts.repairFail'));
    } finally {
      setBusy(false);
    }
  }, [repair, messageApi, t]);

  const onRefresh = useCallback(async () => {
    setBusy(true);
    try {
      const msg = await refresh();
      if (msg?.success) {
        await refetchServers();
        messageApi.success(t('pages.vpngate.toasts.refreshed'));
      } else {
        messageApi.error(msg?.msg || t('pages.vpngate.toasts.refreshFail'));
      }
    } finally {
      setBusy(false);
    }
  }, [refresh, refetchServers, messageApi, t]);

  const onSaveSettings = useCallback(async () => {
    setSavingSettings(true);
    try {
      const msg = await updateSettings({
        ruleMode,
        selectedCountries,
        fallbackEnable,
      });
      if (msg?.success) messageApi.success(t('pages.vpngate.toasts.settingsSaved'));
      else messageApi.error(msg?.msg || t('pages.vpngate.toasts.settingsFail'));
    } finally {
      setSavingSettings(false);
    }
  }, [ruleMode, selectedCountries, fallbackEnable, updateSettings, messageApi, t]);

  const columns: ColumnsType<VPNGateServer> = [
    {
      title: t('pages.vpngate.colCountry'),
      dataIndex: 'countryLong',
      key: 'countryLong',
      render: (_v, row) => (
        <Space>
          <Tag color="blue">{row.countryShort}</Tag>
          <span>{row.countryLong}</span>
        </Space>
      ),
    },
    { title: t('pages.vpngate.colHost'), dataIndex: 'hostName', key: 'hostName' },
    { title: t('pages.vpngate.colIP'), dataIndex: 'ip', key: 'ip' },
    {
      title: t('pages.vpngate.colPing'),
      dataIndex: 'localPing',
      key: 'localPing',
      render: (v: number) => (v > 0 ? `${v} ms` : '—'),
      sorter: (a, b) => a.localPing - b.localPing,
    },
    {
      title: t('pages.vpngate.colSessions'),
      dataIndex: 'numSessions',
      key: 'numSessions',
      render: (v: number) => v,
    },
    { title: t('pages.vpngate.colISP'), dataIndex: 'isp', key: 'isp' },
    {
      title: t('pages.vpngate.colAction'),
      key: 'action',
      render: (_v, row) => {
        const connected = status?.server?.ip === row.ip && Boolean(status?.tunIP);
        return (
          <Button
            type="link"
            disabled={isActive && !connected}
            onClick={() => {
              setSelectedKey(`${row.ip}:${row.port}`);
              void onConnect();
            }}
          >
            {connected ? t('pages.vpngate.connected') : t('pages.vpngate.connect')}
          </Button>
        );
      },
    },
  ];

  const statusColor = isConnecting ? 'processing' : isActive ? 'success' : 'default';
  const statusText = isConnecting
    ? t('pages.vpngate.connecting')
    : isActive
      ? t('pages.vpngate.connected')
      : t('pages.vpngate.notConnected');

  return (
    <>
      <div style={{ padding: 16 }}>
      <Title level={3}>{t('pages.vpngate.title')}</Title>
      <Paragraph type="secondary">{t('pages.vpngate.description')}</Paragraph>

      <Row gutter={16}>
        <Col xs={24} lg={14}>
          <Card
            title={
              <Space>
                <ApiOutlined />
                {t('pages.vpngate.status')}
                <Tag color={statusColor}>{statusText}</Tag>
              </Space>
            }
          >
            {isActive && status?.progress != null && (
              <Progress percent={status.progress} status={isConnecting ? 'active' : 'success'} />
            )}
            <Descriptions column={1} size="small" bordered>
              <Descriptions.Item label={t('pages.vpngate.phase')}>{status?.phase || 'idle'}</Descriptions.Item>
              <Descriptions.Item label={t('pages.vpngate.message')}>{status?.message || '—'}</Descriptions.Item>
              {status?.tunIP && (
                <Descriptions.Item label={t('pages.vpngate.tunIP')}>{status.tunIP}</Descriptions.Item>
              )}
              {status?.tunDev && (
                <Descriptions.Item label={t('pages.vpngate.tunDev')}>{status.tunDev}</Descriptions.Item>
              )}
              {status?.server && (
                <Descriptions.Item label={t('pages.vpngate.node')}>
                  {status.server.countryLong} · {status.server.ip}
                </Descriptions.Item>
              )}
            </Descriptions>

            <Divider />
            <Space wrap>
              <Button
                type="primary"
                icon={<ApiOutlined />}
                loading={busy && isConnecting}
                disabled={isActive}
                onClick={onConnect}
              >
                {t('pages.vpngate.connectSelected')}
              </Button>
              <Button
                danger
                icon={<DisconnectOutlined />}
                loading={busy && !isConnecting}
                disabled={!isActive}
                onClick={onDisconnect}
              >
                {t('pages.vpngate.disconnect')}
              </Button>
              <Button icon={<StopOutlined />} disabled={!isConnecting || busy} onClick={onCancel}>
                {t('pages.vpngate.cancel')}
              </Button>
              <Button icon={<ToolOutlined />} disabled={busy} onClick={onRepair}>
                {t('pages.vpngate.repair')}
              </Button>
            </Space>
          </Card>
        </Col>

        <Col xs={24} lg={10}>
          <Card title={t('pages.vpngate.settings')}>
            <Descriptions column={1} size="small">
              <Descriptions.Item label={t('pages.vpngate.ruleMode')}>
                <Radio.Group
                  value={ruleMode}
                  onChange={(e) => setRuleMode(e.target.value)}
                  optionType="button"
                  buttonStyle="solid"
                >
                  <Radio value="default">{t('pages.vpngate.ruleModeDefault')}</Radio>
                  <Radio value="fixed">{t('pages.vpngate.ruleModeFixed')}</Radio>
                </Radio.Group>
              </Descriptions.Item>
              {ruleMode === 'fixed' && (
                <Descriptions.Item label={t('pages.vpngate.selectedCountries')}>
                  <Select
                    mode="multiple"
                    allowClear
                    style={{ width: '100%' }}
                    placeholder={t('pages.vpngate.selectCountries')}
                    options={countryOptions}
                    value={selectedCountries}
                    onChange={setSelectedCountries}
                  />
                </Descriptions.Item>
              )}
              <Descriptions.Item label={t('pages.vpngate.fallbackEnable')}>
                <Switch checked={fallbackEnable} onChange={setFallbackEnable} />
              </Descriptions.Item>
            </Descriptions>
            <Button
              type="primary"
              loading={savingSettings}
              onClick={onSaveSettings}
              disabled={settingsLoaded === false}
            >
              {t('pages.vpngate.save')}
            </Button>
          </Card>
        </Col>
      </Row>

      <Card
        style={{ marginTop: 16 }}
        title={t('pages.vpngate.servers')}
        extra={
          <Button icon={<ReloadOutlined />} loading={serversLoading || busy} onClick={onRefresh}>
            {t('pages.vpngate.refresh')}
          </Button>
        }
      >
        <Table<VPNGateServer>
          rowKey={(r) => `${r.ip}:${r.port}`}
          columns={columns}
          dataSource={servers}
          loading={serversLoading}
          size="middle"
          rowSelection={{
            type: 'radio',
            selectedRowKeys: selectedKey ? [selectedKey] : [],
            onChange: (keys) => setSelectedKey((keys[0] as string) ?? null),
          }}
          pagination={{ pageSize: 10, showSizeChanger: true }}
          locale={{ emptyText: t('pages.vpngate.emptyServers') }}
          scroll={{ x: 760 }}
        />
      </Card>

    </div>
      {messageContextHolder}
    </>
  );
}
