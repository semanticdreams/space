#ifndef MATRIX_H
#define MATRIX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mx_client mx_client_t;

typedef struct mx_string
{
    const char *data;
    size_t len;
} mx_string_t;

typedef struct mx_error
{
    int32_t code;
    mx_string_t message;
} mx_error_t;

typedef struct mx_result
{
    int32_t ok;
    mx_error_t error;
} mx_result_t;

typedef struct mx_room_list
{
    mx_string_t *room_ids;
    size_t count;
} mx_room_list_t;

typedef void (*mx_client_created_cb)(mx_client_t *client, mx_result_t result, void *user_data);
typedef void (*mx_login_cb)(mx_result_t result, mx_string_t user_id, void *user_data);
typedef void (*mx_sync_cb)(mx_result_t result, void *user_data);
typedef void (*mx_rooms_cb)(mx_result_t result, mx_room_list_t rooms, void *user_data);

void mx_init(void);

void mx_client_create(const char *homeserver_url, mx_client_created_cb cb, void *user_data);
void mx_client_free(mx_client_t *client);

void mx_client_login_password(
    mx_client_t *client,
    const char *username,
    const char *password,
    mx_login_cb cb,
    void *user_data);

void mx_client_sync_once(mx_client_t *client, mx_sync_cb cb, void *user_data);
void mx_client_rooms(mx_client_t *client, mx_rooms_cb cb, void *user_data);

void mx_string_free(mx_string_t value);
void mx_result_free(mx_result_t result);
void mx_room_list_free(mx_room_list_t rooms);

#ifdef __cplusplus
}
#endif

#endif
