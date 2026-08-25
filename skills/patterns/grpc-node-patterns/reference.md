# gRPC Patterns for Node.js / Bun — Reference

Full code for every pattern summarized in `SKILL.md`'s trigger map. Content moved verbatim
from SKILL.md (2026-08-23, 200-LOC cap refactor).

## Proto Definition

```protobuf
// proto/anpr.proto
syntax = "proto3";

package anpr;

service ANPRService {
  rpc DetectPlate (DetectRequest) returns (DetectResponse);
  rpc StreamDetections (StreamRequest) returns (stream DetectionEvent);
  rpc BatchDetect (stream DetectRequest) returns (DetectResponse);
}

message DetectRequest {
  bytes image_data = 1;
  string camera_id = 2;
  int64 timestamp_ms = 3;
}

message DetectResponse {
  string plate = 1;
  float confidence = 2;
  BoundingBox bbox = 3;
}

message BoundingBox {
  int32 x = 1;
  int32 y = 2;
  int32 width = 3;
  int32 height = 4;
}

message StreamRequest {
  string camera_id = 1;
}

message DetectionEvent {
  string plate = 1;
  float confidence = 2;
  int64 detected_at_ms = 3;
}
```

## TypeScript Codegen (Recommended)

Use `@protobuf-ts/plugin` or `ts-proto` for type-safe interfaces:

```bash
# ts-proto (works well with grpc-js)
npm install ts-proto
npx protoc --plugin=node_modules/.bin/protoc-gen-ts_proto \
  --ts_proto_out=./src/generated \
  --ts_proto_opt=outputServices=grpc-js \
  --proto_path=./proto \
  ./proto/anpr.proto
```

## Client Setup

```typescript
import * as grpc from '@grpc/grpc-js'
import { ANPRServiceClient } from './generated/anpr.grpc-client'

// Create once, reuse across requests
const client = new ANPRServiceClient(
  process.env.ANPR_SERVICE_URL ?? 'localhost:50051',
  grpc.credentials.createInsecure()
  // For TLS: grpc.credentials.createSsl()
)

// Unary call — promisified
function detectPlate(imageData: Buffer, cameraId: string): Promise<DetectResponse> {
  return new Promise((resolve, reject) => {
    const deadline = new Date(Date.now() + 5000)  // 5s timeout
    const metadata = new grpc.Metadata()
    metadata.add('x-api-key', process.env.ANPR_API_KEY!)

    client.detectPlate(
      { imageData, cameraId, timestampMs: Date.now() },
      metadata,
      { deadline },
      (error, response) => {
        if (error) reject(error)
        else resolve(response)
      }
    )
  })
}

// Or use a promisify utility
import { promisify } from 'util'
const detectPlateAsync = promisify(client.detectPlate.bind(client))
```

## Without Codegen (proto-loader)

For simpler setups or when codegen is impractical:

```typescript
import * as grpc from '@grpc/grpc-js'
import * as protoLoader from '@grpc/proto-loader'
import path from 'path'

const packageDef = protoLoader.loadSync(
  path.resolve(__dirname, '../proto/anpr.proto'),
  { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true }
)
const proto = grpc.loadPackageDefinition(packageDef).anpr as any
const client = new proto.ANPRService('localhost:50051', grpc.credentials.createInsecure())
```

## Server

```typescript
import * as grpc from '@grpc/grpc-js'
import { ANPRServiceImplementation } from './generated/anpr.grpc-server'

const server = new grpc.Server()

const implementation: ANPRServiceImplementation = {
  detectPlate(call, callback) {
    const { imageData, cameraId } = call.request
    try {
      const result = runDetection(imageData)
      callback(null, { plate: result.plate, confidence: result.score, bbox: result.bbox })
    } catch (err) {
      callback({
        code: grpc.status.INTERNAL,
        message: (err as Error).message,
      })
    }
  },

  streamDetections(call) {
    const { cameraId } = call.request
    const subscription = cameraFeed(cameraId).subscribe({
      next: (event) => call.write({ plate: event.plate, confidence: event.confidence, detectedAtMs: Date.now() }),
      error: (err) => call.destroy(err),
      complete: () => call.end(),
    })
    call.on('cancelled', () => subscription.unsubscribe())
  },
}

server.addService(ANPRServiceService.definition, implementation)
server.bindAsync('0.0.0.0:50051', grpc.ServerCredentials.createInsecure(), (err, port) => {
  if (err) throw err
  console.log(`gRPC server listening on ${port}`)
})
```

## Streaming Patterns

```typescript
// Client-side: consume server stream
const stream = client.streamDetections({ cameraId: 'cam-01' })

stream.on('data', (event: DetectionEvent) => {
  console.log(`Plate: ${event.plate} at ${event.detectedAtMs}`)
})
stream.on('end', () => console.log('Stream ended'))
stream.on('error', (err: grpc.ServiceError) => {
  if (err.code === grpc.status.CANCELLED) return  // intentional cancel
  console.error('Stream error:', err.message)
})

// Cancel the stream
stream.cancel()
```

## Error Status Usage

```typescript
callback({
  code: grpc.status.NOT_FOUND,
  message: `Camera ${cameraId} not found`,
})
```

## Deadlines and Metadata

```typescript
// Always set deadlines on client calls
const deadline = new Date(Date.now() + 10_000)  // 10s

// Pass auth/trace metadata
const metadata = new grpc.Metadata()
metadata.add('authorization', `Bearer ${token}`)
metadata.add('x-request-id', requestId)
metadata.add('x-trace-id', traceId)

client.detectPlate(request, metadata, { deadline }, callback)
```

## Health Check

Use the standard gRPC health protocol:

```typescript
import { HealthImplementation, ServingStatusMap } from 'grpc-health-check'

const statusMap: ServingStatusMap = {
  '': 'SERVING',          // overall
  'anpr.ANPRService': 'SERVING',
}
const healthImpl = new HealthImplementation(statusMap)
healthImpl.addToServer(server)  // v2.x registration (v1.x used server.addService(healthImpl.service, healthImpl))

// Update status (e.g., when model loads)
healthImpl.setStatus('anpr.ANPRService', 'SERVING')
```

## Bun Compatibility

```typescript
// Mostly works on Bun directly — verify against the current Bun version for
// your actual traffic shape (streaming, large messages) before relying on it
import * as grpc from '@grpc/grpc-js'
import * as protoLoader from '@grpc/proto-loader'
```
