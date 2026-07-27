// Command server is a proxyless-gRPC Greeter server.
//
// It uses xds.NewGRPCServer so the gRPC library itself acts as an xDS client:
// it reads the bootstrap file pointed to by GRPC_XDS_BOOTSTRAP (generated on
// GKE by the td-grpc-bootstrap init container) and receives its configuration
// from Cloud Service Mesh. It also serves the standard gRPC health-checking
// protocol, which Cloud Service Mesh's gRPC health checks probe on the
// serving port.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"os"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	xdscreds "google.golang.org/grpc/credentials/xds"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/xds"

	pb "github.com/noyblumenfeld/grpc-hello-app/gen/helloworld"
)

var port = flag.Int("port", 50051, "the port to serve gRPC on")

// greeter implements helloworld.Greeter. The reply embeds the pod hostname so
// that clients can observe per-RPC load balancing across replicas.
type greeter struct {
	pb.UnimplementedGreeterServer
	hostname string
}

func (g *greeter) SayHello(_ context.Context, req *pb.HelloRequest) (*pb.HelloReply, error) {
	return &pb.HelloReply{
		Message: fmt.Sprintf("Hello %s, from %s", req.GetName(), g.hostname),
	}, nil
}

func main() {
	flag.Parse()

	hostname, err := os.Hostname()
	if err != nil {
		hostname = "unknown"
	}

	// xDS server credentials: use mesh-provided (mTLS) security if Cloud
	// Service Mesh sends it, otherwise fall back to plaintext.
	creds, err := xdscreds.NewServerCredentials(xdscreds.ServerOptions{
		FallbackCreds: insecure.NewCredentials(),
	})
	if err != nil {
		log.Fatalf("failed to create xDS server credentials: %v", err)
	}

	server, err := xds.NewGRPCServer(grpc.Creds(creds))
	if err != nil {
		log.Fatalf("failed to create xDS-enabled gRPC server: %v", err)
	}

	pb.RegisterGreeterServer(server, &greeter{hostname: hostname})

	// gRPC health-checking protocol, probed by the Cloud Service Mesh
	// gRPC health check on the serving port.
	healthServer := health.NewServer()
	healthServer.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
	healthpb.RegisterHealthServer(server, healthServer)

	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("failed to listen on :%d: %v", *port, err)
	}

	log.Printf("greeter server (%s) listening on :%d", hostname, *port)
	if err := server.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
