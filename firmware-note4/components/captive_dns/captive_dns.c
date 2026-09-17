#include "captive_dns.h"

#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "esp_netif.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "lwip/inet.h"
#include "lwip/sockets.h"

static const char* kTag = "captive_dns";

typedef struct {
    const char* netif_key;
} captive_dns_context_t;

static size_t question_end(const uint8_t* packet, size_t length) {
    size_t offset = 12;
    while (offset < length) {
        const uint8_t label_length = packet[offset++];
        if (label_length == 0) break;
        if ((label_length & 0xC0) != 0 || offset + label_length > length) return 0;
        offset += label_length;
    }
    return offset + 4 <= length ? offset + 4 : 0;
}

static size_t make_reply(const uint8_t* request, size_t request_length,
                         uint8_t* reply, size_t reply_capacity,
                         uint32_t address) {
    if (request_length < 12) return 0;

    // 回复只保留头部和唯一的问题段，问题数不为 1 的请求无法据此构造合法回复，直接忽略。
    if (request[4] != 0 || request[5] != 1) return 0;

    const size_t end = question_end(request, request_length);
    if (end == 0) return 0;

    static const uint8_t answer_prefix[] = {
        0xC0, 0x0C,       // compressed pointer to the requested name
        0x00, 0x01,       // A record
        0x00, 0x01,       // IN class
        0x00, 0x00, 0x00, 0x3C,  // 60 second TTL
        0x00, 0x04        // IPv4 payload length
    };

    if (end + sizeof(answer_prefix) + 4 > reply_capacity) return 0;

    // 只复制头部和问题段：请求附带的 additional 记录（如 EDNS0 OPT）若原样保留，
    // 追加的 A 记录就会落在 additional 段之后，回复结构错误。
    memcpy(reply, request, end);
    reply[2] = (uint8_t)((reply[2] & 0x79) | 0x80);  // response, standard query
    reply[3] = (uint8_t)((reply[3] & 0x10) | 0x80);  // recursion available

    // ANCOUNT、NSCOUNT、ARCOUNT 先清零，只有 A 查询再把 ANCOUNT 置 1。
    memset(reply + 6, 0, 6);

    const uint16_t type = (uint16_t)((request[end - 4] << 8) | request[end - 3]);
    const uint16_t klass = (uint16_t)((request[end - 2] << 8) | request[end - 1]);
    if (type != 1 || klass != 1) return end;

    reply[7] = 1;
    memcpy(reply + end, answer_prefix, sizeof(answer_prefix));
    memcpy(reply + end + sizeof(answer_prefix), &address, 4);
    return end + sizeof(answer_prefix) + 4;
}

static void captive_dns_task(void* parameter) {
    captive_dns_context_t* context = (captive_dns_context_t*)parameter;
    const int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
    if (sock < 0) {
        ESP_LOGE(kTag, "socket failed: errno %d", errno);
        free(context);
        vTaskDelete(NULL);
        return;
    }

    struct sockaddr_in address = {
        .sin_family = AF_INET,
        .sin_port = htons(53),
        .sin_addr = {.s_addr = htonl(INADDR_ANY)},
    };
    if (bind(sock, (struct sockaddr*)&address, sizeof(address)) < 0) {
        ESP_LOGE(kTag, "bind failed: errno %d", errno);
        close(sock);
        free(context);
        vTaskDelete(NULL);
        return;
    }

    ESP_LOGI(kTag, "wildcard DNS ready");
    while (true) {
        uint8_t request[256];
        struct sockaddr_storage source = {};
        socklen_t source_length = sizeof(source);
        const int received = recvfrom(sock, request, sizeof(request), 0,
                                      (struct sockaddr*)&source, &source_length);
        if (received <= 0) continue;

        esp_netif_t* netif = esp_netif_get_handle_from_ifkey(context->netif_key);
        esp_netif_ip_info_t info = {};
        if (!netif || esp_netif_get_ip_info(netif, &info) != ESP_OK) continue;

        uint8_t reply[272];
        const size_t reply_length = make_reply(
            request, (size_t)received, reply, sizeof(reply), info.ip.addr);
        if (reply_length > 0) {
            sendto(sock, reply, reply_length, 0,
                   (struct sockaddr*)&source, source_length);
        }
    }
}

void start_captive_dns_server(const char* netif_key) {
    if (!netif_key) return;
    captive_dns_context_t* context = calloc(1, sizeof(captive_dns_context_t));
    if (!context) return;
    context->netif_key = netif_key;
    if (xTaskCreate(captive_dns_task, "captive_dns", 4096, context, 5, NULL) != pdPASS) {
        free(context);
    }
}
