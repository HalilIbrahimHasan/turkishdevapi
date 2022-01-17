package get_http_request_method;

import base_urls.HerokuappBaseUrl;
import io.restassured.response.Response;
import org.junit.Test;

import static io.restassured.RestAssured.given;
import static org.junit.Assert.*;

public class Get02 extends HerokuappBaseUrl {



    /*

            Given https://restful-booker.herokuapp.com/booking/1001

            When user sends a GET request to the url

            Then HTTP status code should be 404

            And   response body contains "Not Found"

            And status line should be HTTP/1.1 404 Not Found

            And body does not contain "techproed"

            And Server is "Cowboy"
             */



    @Test
    public void get02(){

        //Set the url  / url olustur
        spec.pathParams("bir", "booking", "iki", 1001);

        //Set the expected data / beklenen datayi olustur


        //Send the Get request and Get the response  / Get Request yapiniz ve Response aliniz
        Response response = given().spec(spec).when().get("/{bir}/{iki}");


        //validation yap / Control et / assert et
        response.then().assertThat().statusCode(404).statusLine("HTTP/1.1 404 Not Found");


        System.out.println(response.asString());

        assertEquals("Data birbiri ile uyum icerisinde degil","Not Found", response.asString());

        assertTrue(response.asString().contains("Not Found"));

        System.out.println("Not Found".contains("Techproed"));
        assertFalse(response.asString().contains("techproed"));

        System.out.println(response.getHeader("Server"));


        assertEquals(response.getHeader("Server"), "Cowboy");

    }




}
