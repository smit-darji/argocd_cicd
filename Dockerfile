# Use the official Nginx image
FROM nginx:latest

# Remove default Nginx website
RUN rm -rf /usr/share/nginx/html/*

# Copy your frontend files into the Nginx web root
COPY index.html /usr/share/nginx/html/

# Expose port 80
EXPOSE 80
