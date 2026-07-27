// Command server is the Greeter server of a proxyless Cloud Service Mesh
// deployment.
//
// In proxyless CSM, xDS drives the *client* side: clients resolve
// xds:///<hostname> through the control plane and load-balance per-RPC across
// this server's pod IPs (registered in a NEG). The server itself serves plain
// gRPC plus the standard health-checking protocol, which the mesh's gRPC
// health check probes on the serving port. (xds.NewGRPCServer is only needed
// when server-side security policies are configured — without them the
// control plane sends no server Listener resource and an xDS-enabled server
// would stay NOT_SERVING.)
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"os"

	"google.golang.org/grpc"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"

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

	server := grpc.NewServer()
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
