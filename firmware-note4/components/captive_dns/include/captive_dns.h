#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Starts a small wildcard DNS server which resolves IPv4 host names to netif. */
void start_captive_dns_server(const char* netif_key);

#ifdef __cplusplus
}
#endif
