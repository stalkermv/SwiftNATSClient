#include "include/shim.h"
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "util.h"

enum {
    seedLength = 58,
    rawKeyLength = 32,
    seedPrefix = 18 << 3,
    userPrefix = 20 << 3,
    publicKeyLength = 56
};

static const char base32Alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

static void encodePublicKey(const unsigned char *bytes, char *output)
{
    uint32_t buffer = 0;
    int bits = 0;
    for (size_t i = 0; i < 1 + rawKeyLength + 2; i++) {
        buffer = (buffer << 8) | bytes[i];
        bits += 8;
        while (bits >= 5) {
            bits -= 5;
            *output++ = base32Alphabet[(buffer >> bits) & 31];
        }
    }
    *output = '\0';
}

static natsStatus derivePublicKey(const char *seed, char *publicKey)
{
    // The 58th Base32 character contains three data bits and two zero bits.
    if (strspn(seed, base32Alphabet) != seedLength || seed[seedLength] != '\0'
        || strchr("AEIMQUY4", seed[seedLength - 1]) == NULL) {
        return NATS_INVALID_ARG;
    }

    char decoded[2 + rawKeyLength + 2] = {0};
    int length = 0;
    natsStatus status = nats_Base32_DecodeString(seed, decoded, sizeof(decoded), &length);
    unsigned char *bytes = (unsigned char *)decoded;
    unsigned char prefix = ((bytes[0] & 7) << 5) | (bytes[1] >> 3);
    uint16_t checksum = bytes[sizeof(decoded) - 2] | (bytes[sizeof(decoded) - 1] << 8);
    if (status != NATS_OK || length != sizeof(decoded)
        || (bytes[0] & 248) != seedPrefix || prefix != userPrefix
        || (bytes[1] & 7) != 0
        || !nats_CRC16_Validate(bytes, sizeof(decoded) - 2, checksum)) {
        OPENSSL_cleanse(decoded, sizeof(decoded));
        return NATS_INVALID_ARG;
    }

    EVP_PKEY *key = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, NULL, bytes + 2, rawKeyLength);
    OPENSSL_cleanse(decoded, sizeof(decoded));
    if (key == NULL) {
        return NATS_ERR;
    }

    unsigned char encoded[1 + rawKeyLength + 2] = {userPrefix};
    size_t publicBytes = rawKeyLength;
    int result = EVP_PKEY_get_raw_public_key(key, encoded + 1, &publicBytes);
    EVP_PKEY_free(key);
    if (result != 1 || publicBytes != rawKeyLength) {
        return NATS_ERR;
    }

    checksum = nats_CRC16_Compute(encoded, 1 + rawKeyLength);
    encoded[1 + rawKeyLength] = (unsigned char)checksum;
    encoded[2 + rawKeyLength] = (unsigned char)(checksum >> 8);
    encodePublicKey(encoded, publicKey);
    return NATS_OK;
}

static natsStatus signNonce(char **error, unsigned char **signature, int *length,
                            const char *nonce, void *seed)
{
    return nats_Sign(seed, nonce, signature, length);
}

natsStatus swiftNATS_SetUserNKey(natsOptions *options, const char *seed, char **ownedSeed)
{
    if (options == NULL || seed == NULL || ownedSeed == NULL) {
        return NATS_INVALID_ARG;
    }

    char publicKey[publicKeyLength + 1];
    natsStatus status = derivePublicKey(seed, publicKey);
    if (status != NATS_OK) {
        return status;
    }

    char *copy = strdup(seed);
    if (copy == NULL) {
        return NATS_NO_MEMORY;
    }

    status = natsOptions_SetNKey(options, publicKey, signNonce, copy);
    if (status != NATS_OK) {
        swiftNATS_DestroyNKeySeed(copy);
        return status;
    }
    *ownedSeed = copy;
    return NATS_OK;
}

void swiftNATS_DestroyNKeySeed(char *seed)
{
    OPENSSL_cleanse(seed, seedLength + 1);
    free(seed);
}
